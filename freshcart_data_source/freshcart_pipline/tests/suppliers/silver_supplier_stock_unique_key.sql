-- One row per supplier / product / store / stock_date
select supplier, product_id, store_id, stock_date, count() as n
from {{ ref("silver_supplier_stock") }}
group by supplier, product_id, store_id, stock_date
having n > 1
