# SQL tuning module: Finance's weekly report

Every Monday, Finance runs `legacy_finance_report.sql` directly on the company's
production database. It takes minutes, the app becomes slow while it runs, and
nobody dares to touch it. Make it fast.

## Rules

1. **Same results.** Your version must return exactly the same rows. Prove it.
2. **Measure, don't guess.** Every change must be justified by an execution plan.
3. **It is a production database.** Anything you add (indexes...) costs something for
   the app that writes to it. Say what, and how you would add it without blocking the app.

## Getting started

    docker compose exec source-db psql -U freshcart -d freshcart_source

```sql
\timing on
EXPLAIN (ANALYZE, BUFFERS)
<the SELECT from legacy_finance_report.sql>;
```

Run every measurement 3 times and report the warm timing (the first run reads from disk).
<https://explain.dalibo.com> (free) turns a text plan into a readable diagram.

## Proving the results are identical

```sql
SET TIME ZONE 'Africa/Cairo';
CREATE TABLE public.legacy_result AS <legacy SELECT without ORDER BY>;
SELECT count(*) FROM (SELECT * FROM public.legacy_result EXCEPT ALL SELECT * FROM (<your query>) t) a;  -- 0
SELECT count(*) FROM (SELECT * FROM (<your query>) t EXCEPT ALL SELECT * FROM public.legacy_result) b;  -- 0
```

## What to hand in (folder `sql_tuning/`)

| File | Content |
|---|---|
| `tuned_finance_report.sql` | your final query |
| `migrations.sql` | every index or object you added, each with a one-line justification |
| `plans/before.txt`, `plans/after.txt` | full `EXPLAIN (ANALYZE, BUFFERS)` output |
| `REPORT.md` | diagnosis (with numbers from the plans), changes, before/after table, the two EXCEPT counts, trade-offs, and: should this report run on the production database at all? |

## Grading

| Criterion | Weight |
|---|---|
| Diagnosis backed by the plans | 35% |
| Measured improvement, results proven identical | 30% |
| Quality of the changes (justified, minimal, safe to deploy) | 20% |
| Clarity of the report, including the long-term recommendation | 15% |
