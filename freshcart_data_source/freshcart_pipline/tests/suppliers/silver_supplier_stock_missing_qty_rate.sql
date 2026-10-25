-- GENERAL normally sends 'N/A' for about 3% of rows. Warn when a day's file has more
-- than 10% missing quantities: a broken file must not look like a normal day.
{{ config(severity="warn") }}

select
    supplier,
    stock_date,
    count() as rows_n,
    countIf(is_qty_missing) as missing_qty,
    round(missing_qty / rows_n, 3) as missing_share
from {{ ref("silver_supplier_stock") }}
group by supplier, stock_date
having missing_share > 0.10
