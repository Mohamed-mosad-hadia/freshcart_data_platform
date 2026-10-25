-- Quantities can't be negative and the reorder level must be positive
select supplier, product_id, store_id, stock_date, quantity_on_hand, reorder_level
from {{ ref("silver_supplier_stock") }}
where quantity_on_hand < 0 or reorder_level <= 0 or unit_cost <= 0
