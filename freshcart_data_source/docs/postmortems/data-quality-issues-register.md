# Data quality issues register

Known data problems that are not outages: found during EDA, handled in silver, and watched
by tests. Incidents with late or wrong data have their own postmortem in this folder.

## Incidents and company changes (postmortems)
| Date | Postmortem | Severity |
|---|---|---|
| 2026-10-17 | [GENERAL supplier changed its file layout](2026-10-17-general-supplier-file-layout-change.md) | SEV-3 |
| 2026-10-19 | [New store 7 (Cairo - Heliopolis) opened](2026-10-19-new-store-heliopolis.md) | SEV-3 |
| 2026-10-23 | [FX API `/v1/currencies` outage](2026-10-23-fx-api-currencies-outage.md) | SEV-2 |
| 2026-10-24 | [Order lines and payments arrive one night before their order](2026-10-24-late-arriving-orders.md) | SEV-3 |
| 2026-10-24 | [Duplicated payments in the source](2026-10-24-duplicate-payments.md) | SEV-2 |

## Data issues handled in silver
| # | Source | Issue | Evidence | Handling | Watched by |
|---|---|---|---|---|---|
| 1 | `app.customers` | QA test account in production (customer 150003) | EDA on customers | Its orders, order lines and payments are excluded from silver | `silver_customers_no_test_accounts` |
| 2 | `app.customers` | Same person with two accounts (150001 = 3, 150002 = 7) | EDA on customers | Orders remapped to the original customer in `silver_orders` | relationships `silver_orders.customer_id` |
| 3 | `app.customers` | Phone numbers typed in many formats; untrimmed / inconsistent text | `analyses/app/customers_eda_quality.sql` | Standardised in `silver_customers` | `silver_customers_phone_format`, `silver_customers_text_clean` |
| 4 | `app.products` | 6 inactive products still sold at normal rate after deactivation (about 1,000 to 3,300 order lines each) | `analyses/app/products_eda_quality.sql` | Kept as real sales; gold must not filter sales by `is_active` | `silver_products_inactive_still_sold` (warn) |
| 5 | GENERAL stock files | `N/A` instead of a quantity in about 3% of rows (8,083 rows), every month, all products | `analyses/supplier/suppliers_eda_quality.sql` | `quantity_on_hand` NULL + `is_qty_missing`; never counted as a stockout | `silver_supplier_stock_missing_qty_rate` (warn > 10% per day) |
| 6 | FRESH + GENERAL files | Stock rows for stores 5 (Riyadh) and 6 (Dubai) before they opened (35,280 rows from 2024-10-13) | supplier EDA | `is_before_store_opening`; exclude from stockout metrics | column `not_null` test; gold filter |
| 7 | GENERAL files | Different format from FRESH: `;` separator, `dd/mm/yyyy` dates, decimal comma | supplier EDA | Converted in `silver_supplier_stock` | `silver_supplier_stock_values`, `not_null` on dates |
| 8 | FX API | No rates on Friday / Saturday (business days only); weekend requests return Thursday's rate | FX EDA on `bronze_fx_api.rates` | Gold must use the last published rate for weekend days | `silver_fx_history_complete_business_days` |

## Platform risks found (our code)
| # | Where | Risk | Suggested fix |
|---|---|---|---|
| 1 | `ingestion/suppliers/Load/Load_general_suppliers.py` (`ingest_general_supplier_files`) | A failed GENERAL file is only logged: it is never added to `failures` and no error is raised, so the Airflow task succeeds and the file is silently missing | Append to `failures` in the `except` block and raise at the end, as `Load_fresh_suppliers.py` does |
| 2 | Supplier loader | A new CSV layout creates a new Bronze table silently | Log/alert on new table; dbt test `silver_supplier_stock_new_layout` (warn) |
| 3 | FX ingestion | See action items of the FX outage postmortem (single task, short retries, wall-clock date, broken `email_on_failure`) | See [FX postmortem](2026-10-23-fx-api-currencies-outage.md), section 8 |
