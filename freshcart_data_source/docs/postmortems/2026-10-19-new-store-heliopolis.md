# Postmortem: new store 7 (FreshCart Cairo - Heliopolis) opened

> Blameless: describe what the SYSTEM allowed to happen, not who made a mistake.

| | |
|---|---|
| Date of incident | 2026-10-19 (store opening) |
| Authors | Ahmed Nabil, Mohamed Mosaad |
| Severity | SEV-3 (company change; no data late, wrong or lost) |

## 1. Summary
FreshCart opened a seventh store, **FreshCart Cairo - Heliopolis** (`store_id = 7`), on
2026-10-19. The project brief lists six stores. The new store appeared in
`bronze_app.stores` and, from 2026-10-19, in both supplier files, which grew from 360 to 420
rows per day (60 products x 7 stores). Nothing failed and nothing is wrong, but every model
that assumes "6 stores" must keep working with 7.

## 2. Impact
- **Late / wrong / lost:** nothing.
  - `bronze_app.stores` has store 7 with `opened_at = 2026-10-19`.
  - FRESH and GENERAL files include store 7 from 2026-10-19 (no rows before its opening).
  - `silver_supplier_stock` relationship test `store_id -> silver_stores` passes.
- **Watch:** gold models (store dimension, revenue per store, stockouts per store), dashboards
  and any hard-coded list of stores or currencies.

## 3. Timeline (Cairo time)
| Time | Event |
|---|---|
| 2026-10-19 | Store 7 opens; first supplier files with 420 rows (`fresh_stock_2026-10-19.csv`, `GENERAL_STOCK_20261019.csv`) |
| 2026-10-20 00:15 | Supplier files of 2026-10-19 ingested (no error) |
| 2026-10-25 | Detected during the supplier EDA (rows per file 360 -> 420, new `store_id` 7) and confirmed in `bronze_app.stores` |

## 4. Detection
Detected by manual EDA about 6 days after the opening. No test failed because the store
exists in the stores table (relationships pass) and no test hard-codes the number of stores.

What would have detected it sooner: a warn test on "new store_id seen" or on a change in
rows per supplier file.

## 5. Root cause and contributing factors
**Root cause:** a normal business change (new store), not announced to the data team.

**Contributing factors:**
- The project brief describes 6 stores, so it is easy to hard-code 6 stores in reports.
- Supplier files have no header row or metadata that announces a new store.

## 6. Recovery
No repair needed. Checks done:
- Store 7 exists in `bronze_app.stores` / `silver_stores` with its opening date.
- `silver_supplier_stock.is_before_store_opening` is false for all store 7 rows.

Still to check when gold is built:
- store 7 appears in the store dimension and in revenue per store;
- its currency (from `silver_stores.currency`) is converted with the right FX rate;
- the `silver_stores` `accepted_values` tests on `country` / `currency` still pass (they fail if
  the new store uses a new country or currency, which is the intended alarm).

## 7. What went well / what went badly / where we got lucky
**Went well**
- Loaders and silver are driven by the data, not by a fixed list of stores.
- Store opening date is available, so pre-opening rows can be flagged.

**Went badly**
- Found 6 days late, by chance.

**Where we got lucky**
- The new store uses an existing country, so no FX or country mapping broke.

## 8. Action items
| # | Action | Prevent / detect / mitigate | Owner | Priority |
|---|---|---|---|---|
| 1 | Build the gold store dimension from `silver_stores` (never a hard-coded list of 6 stores) | Prevent | Mohamed Mosaad | High |
| 2 | Warn test: a `store_id` appears in orders or supplier files for the first time | Detect | Ahmed Nabil | Medium |
| 3 | Mention the 7th store in the final demo and README (brief says 6) | Mitigate | Ahmed Nabil | Low |
