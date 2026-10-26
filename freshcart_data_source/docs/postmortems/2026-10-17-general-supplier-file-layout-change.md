# Postmortem: GENERAL supplier changed its stock file layout without notice

> Blameless: describe what the SYSTEM allowed to happen, not who made a mistake.

| | |
|---|---|
| Date of incident | 2026-10-17 (first file in the new layout) |
| Authors | Ahmed Nabil, Mohamed Mosaad |
| Severity | SEV-3 (no data late, wrong or lost; risk of silently missing data in silver) |

## 1. Summary
From the file of 2026-10-17, the GENERAL supplier changed the layout of
`GENERAL_STOCK_YYYYMMDD.csv`: the column `Qty` was renamed `QtyOnHand` and a new column
`UnitCost` was added (decimal comma, e.g. `11,33`). Nobody announced it. Our loader did not
fail: it creates one Bronze table per CSV header, so the new files went into a new table.
Nothing was lost, but any model that only read the old table would have shown GENERAL stock
stopping on 2026-10-16 without any error.

## 2. Impact
- **Late / wrong / lost:** nothing. All 8 files in the new layout (2026-10-17 to 2026-10-24,
  3,240 rows) are in `bronze_suppliers.general_stock_39c8d28c0bd9`; the 734 older files
  (264,240 rows) stay in `bronze_suppliers.general_stock_7e84d7c978e4`.
- **Risk avoided:** `silver_supplier_stock` was built after the change and maps both layouts.
  A silver model written before the change would have silently dropped GENERAL stock from
  2026-10-17 (half of all products: Beverages, Frozen, Household, Pantry, Personal Care, Snacks).
- **New information:** `UnitCost` is available from 2026-10-17 only.

## 3. Timeline (Cairo time)
| Time | Event |
|---|---|
| 2026-10-17 | First GENERAL file in the new layout (`GENERAL_STOCK_20261017.csv`) |
| 2026-10-20 00:15 | Loader ingests the files of 2026-10-10 to 2026-10-19; creates table `general_stock_39c8d28c0bd9` for the new header (no error) |
| 2026-10-25 | Detected during the supplier EDA: two `schema_hash` values for GENERAL in `bronze_suppliers.ingested_files` |
| 2026-10-25 | `silver_supplier_stock` maps both layouts; warn test for unknown layouts added |

## 4. Detection
Detected by manual EDA, about 8 days after the change. Nothing alerted, because the loader
handled the new header as designed.

What would have detected it on the first night:
- an alert (or log warning) when the loader creates a new Bronze table for a new header;
- the dbt test `silver_supplier_stock_new_layout` (added now, severity `warn`): it fails as soon
  as `ingested_files` contains a `schema_hash` that silver does not read.

## 5. Root cause and contributing factors
**Root cause (outside our control):** the supplier changed its file format without notice.

**Five whys:**
1. Why could GENERAL stock have disappeared from silver? Because the new files are in a new table.
2. Why a new table? The loader keys Bronze tables by the CSV header (schema hash), to keep data "as received".
3. Why is that a risk? Silver must list every layout table explicitly; a new one is not picked up automatically.
4. Why was it not noticed for 8 days? No alert when a new layout table is created.
5. Why no alert? The loader treats a new header as normal, not as an event to report.

**Contributing factors:**
- GENERAL files use different conventions from FRESH (`;` separator, `dd/mm/yyyy` dates,
  decimal comma), so every change needs explicit mapping.
- The unit of `UnitCost` is not documented (it looks like USD: about 69% of the catalogue USD price).

## 6. Recovery
No data repair needed. Changes made:
- `models/silver/suppliers/silver_supplier_stock.sql` maps `general_v1_qty` (`Qty`) and
  `general_v2_qtyonhand` (`QtyOnHand`, `UnitCost` with `,` converted to `.`) to the same columns.
- `source.yml` declares both tables (`general_stock_qty`, `general_stock_qtyonhand`).

Verification: `silver_supplier_stock` has 534,960 rows = 267,480 (FRESH) + 264,240 + 3,240
(GENERAL); test `silver_supplier_stock_every_day_both_suppliers` passes (every day has both suppliers).

## 7. What went well / what went badly / where we got lucky
**Went well**
- The loader validated the header, did not crash, and lost nothing.
- Bronze kept the files exactly as received, so the change is fully visible.

**Went badly**
- No alert when a new layout appeared; found by chance during EDA.

**Where we got lucky**
- Silver for suppliers had not been written yet, so no wrong numbers were ever published.

## 8. Action items
| # | Action | Prevent / detect / mitigate | Owner | Priority |
|---|---|---|---|---|
| 1 | dbt test `silver_supplier_stock_new_layout` (warn) on unknown `schema_hash` (done) | Detect | Ahmed Nabil | High |
| 2 | Log a WARNING / send an alert in the supplier loader when `ensure_data_table` creates a new table | Detect | Mohamed Mosaad | Medium |
| 3 | Confirm the currency of `UnitCost` with the supplier; until then document it as "likely USD" | Prevent | Ahmed Nabil | Low |
