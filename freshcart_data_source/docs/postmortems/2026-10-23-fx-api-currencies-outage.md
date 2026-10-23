# Postmortem: FX API `/v1/currencies` outage blocked the nightly FX ingestion

> Blameless: describe what the SYSTEM allowed to happen, not who made a mistake.

| | |
|---|---|
| Date of incident | 2026-10-23 |
| Authors | Ahmed Nabil, Mohamed Mosaad |
| Severity | SEV-2 (FX data late; no data wrong or lost) |

## 1. Summary
On the evening of 2026-10-23 the external exchange-rate provider (`fx-api`) had a major
incident: its `/v1/currencies` endpoint answered every request with HTTP 503
("service unavailable: major incident, our engineers are working on it"), while its
`/health` endpoint kept answering 200 OK. Our nightly Airflow task `Fx_api_ingestion_dag`
failed after 4 attempts in about 4 minutes, so the exchange rates for 2026-10-22 were not
loaded into Bronze. Revenue in USD for that day cannot be calculated until the rates are
loaded. Nothing was loaded incorrectly: the data is late, not wrong.

## 2. Impact
- **Late:** `bronze_fx_api.currencies`, `bronze_fx_api.rates` (business date 2026-10-22)
  and `bronze_fx_api.history` got no new batch from the 2026-10-23 run. Everything built on
  them in dbt (silver FX tables, USD revenue in gold) is stale until recovery.
  Lateness: from the planned load at 22:58 (Oct 23) until recovery (see timeline).
- **Partially loaded:** one health-check row (batch `80c7ee4d-5cc5-476e-b86f-e3f2d4872469`)
  was inserted into `bronze_fx_api.health_check` before the failure. It is correct data
  (the API was "healthy"), so it is harmless.
- **Wrong or lost:** nothing. The loaders insert only after a successful API response,
  so no empty or error payloads reached Bronze. Previous days are untouched: the runs of
  2026-10-22 (scheduled and manual) finished with "FX API ingestion completed successfully".
- **Other sources:** database and supplier ingestion are separate tasks and were not affected.
- **Blocked:** because the DAG uses `depends_on_past=True`, every later
  `Fx_api_ingestion_dag` run waits until this task succeeds.

## 3. Timeline (Cairo time)
| Time | Event |
|---|---|
| 2026-10-22 22:58 | Last successful FX load (run `manual__2026-10-22T19:58:51`, "FX API ingestion completed successfully") |
| 2026-10-23 22:58:07 | Run `scheduled__2026-10-23` attempt 1 starts; health check OK, currencies request returns 503 (`attempt=1.log`) |
| 22:59:23 / 23:00:31 / 23:01:39 | Attempts 2, 3, 4: same 503 on `/v1/currencies` each time |
| 23:01:45 | First failure becomes permanent: `RetryError ... Max retries exceeded with url: /v1/currencies (Caused by ResponseError('too many 503 error responses'))` (`attempt=4.log`) |
| 23:01:48 | Detected: failure-callback e-mail "🚨 [Airflow Alert] Task Failed" sent via Gmail |
| 23:01:48 | Airflow's built-in `email_on_failure` e-mail failed with `SSL: WRONG_VERSION_NUMBER` (second alert lost) |
| 23:16:45 | Investigation: manual requests from the Airflow worker confirm `/health` = 200, `/v1/currencies` = 503 "major incident" |
| 23:25:19 | Task cleared and re-run by hand several times; attempt 8 fails with the same 503 (`attempt=8.log`) |
| ~23:30 | Investigation: `/v1/currencies`, `/v1/rates` and `/v1/rates/history` all return 503 "major incident"; no `Retry-After` header, so no announced end time |
| _TBD_ | Recovery started: `/v1/currencies` returns 200 again; task cleared |
| _TBD_ | Data verified complete and correct |

## 4. Detection
Detected by our `on_failure_callback` e-mail about 4 minutes after the first failed
request, which was only after all retries were used up. A human then confirmed the cause
by calling the API by hand.

What would have detected it sooner or more clearly:
- Our health check only calls `/health`, which stayed green during the outage. Checking
  the real endpoints (`/v1/currencies`, `/v1/rates`) would show the outage directly.
- Including the HTTP status and response body ("major incident") in the alert would
  have made it clear immediately that the problem was the provider, not our code.

## 5. Root cause and contributing factors
**Root cause (outside our control):** a major incident at the FX provider made
`/v1/currencies` return HTTP 503.

**Five whys:**
1. Why were rates not loaded? Because the FX task failed.
2. Why did the task fail? Because `/v1/currencies` returned 503 and our loaders run in a
   fixed sequence (health → currencies → rates → history) inside **one** task, so the
   currencies failure stopped rates and history too. (In this incident all data endpoints
   were down, so splitting would not have saved the day, but it will for single-endpoint
   failures.)
3. Why did retries not save us? Our retry window was about 4 minutes in total (3 HTTP
   retries with 1–4 s backoff, plus 3 Airflow retries 1 minute apart). That is far too
   short for a provider incident, which lasts tens of minutes to hours.
4. Why did it block more than one day? `depends_on_past=True` makes every following FX
   run wait for this one.
5. Why is recovery harder than "just clear the task"? `run_ingestion` requests
   *yesterday in Cairo* based on the wall clock, not the run's logical date. If the task
   is re-run on a later day, it would fetch the wrong day and 2026-10-22 would stay missing.

**Other contributing factors:**
- Our health check gave a false "all good" (`/health` = 200 while the data endpoints were down).
- The second alert channel (built-in `email_on_failure`) was broken: the `smtp_default`
  connection uses SSL by default, but Gmail port 587 expects STARTTLS.

## 6. Recovery
Steps (fill in the times as they happen):
1. Check that the provider has recovered, from the Airflow worker:
   `GET http://fx-api:8000/v1/currencies` with header `X-API-Key` returns 200.
2. If recovery happens **on 2026-10-23 (Cairo)**: clear `Fx_api_ingestion_dag` for run
   `scheduled__2026-10-23T00:00:00+00:00` in the Airflow UI.
   If it happens **later**: re-run the FX ingestion for the missing date explicitly,
   e.g. `python -m ingestion.fx_api.main --rates-date 2026-10-22` inside the worker, and
   then mark the task as success (or apply action item 3 first and clear it normally).
3. Let the following runs (blocked by `depends_on_past`) continue.

Verification that every day is complete and correct:
- `bronze_fx_api.rates` has exactly one successful batch for every `requested_date` from
  the course start to 2026-10-22 (no gaps, no duplicates per date).
- `bronze_fx_api.currencies` has a new batch with `fetched_at` after the recovery time.
- `bronze_fx_api.history` covers 2026-10-22.
- Re-run dbt and check that USD revenue for 2026-10-22 is filled for every store.

## 7. What went well / what went badly / where we got lucky
**Went well**
- The loaders only insert after a successful response, so no bad data reached Bronze.
- The failure-callback e-mail worked and contained the exact error.
- FX ingestion is separate from database and supplier ingestion, so those were not affected.

**Went badly**
- One API endpoint failing stopped all four FX loads.
- The retry window (about 4 minutes) was much shorter than a realistic outage.
- The health check reported "OK" during the outage.
- The built-in e-mail alert failed with an SSL error.
- Re-running on a later day would fetch the wrong date, because the date comes from the wall clock.

**Where we got lucky**
- The outage happened at the end of the course day while we were watching, not in the
  middle of a long unattended backfill.
- The provider returned a clear error message, so the diagnosis was quick.

## 8. Action items
| # | Action | Prevent / detect / mitigate | Owner | Priority |
|---|---|---|---|---|
| 1 | Split `Fx_api_ingestion_dag` into separate tasks (health, currencies, rates, history) so a currencies outage does not block rates | Mitigate | Ahmed Nabil | High |
| 2 | Longer retries on FX tasks: `retries=6`, `retry_delay=5 min`, `retry_exponential_backoff=True`, `max_retry_delay=1 h` | Mitigate | Mohamed Mosaad | High |
| 3 | Pass the run date to the loader (`op_kwargs={"requested_date": "{{ ds }}"}`) so re-runs and backfills fetch the correct day | Prevent | Ahmed Nabil | High |
| 4 | Fix the built-in e-mail: remove `email_on_failure`/`email` from `default_args` (callback already alerts) or add `"extra":{"disable_ssl":true}` to `AIRFLOW_CONN_SMTP_DEFAULT` | Detect | Mohamed Mosaad | Medium |
| 5 | Make the health check call a real data endpoint and include HTTP status and response body in the alert | Detect | Ahmed Nabil | Medium |
| 6 | Add a dbt freshness/completeness test: one `rates` batch per day, no gaps | Detect | Mohamed Mosaad | Medium |
