{{ config(materialized="table", tags=["gold", "inventory"], schema="gold_inventory") }}

-- Periodic snapshot: one row per product, store and day (stock on the shelf at 22:00).
-- Rows reported for days before the store opened are excluded (supplier file error).
-- Stockout = quantity 0; 'N/A' quantities (is_qty_missing) are never stockouts.
-- Stockouts per store / category / supplier:
--   select store_id, category, supplier, countIf(is_stockout) ... group by ...
select
    s.stock_date,
    s.store_id,
    s.product_id,
    s.supplier,
    p.category,
    s.quantity_on_hand,
    s.reorder_level,
    s.unit_cost,
    s.is_stockout,
    s.is_below_reorder,
    s.is_qty_missing
from {{ ref("silver_supplier_stock") }} as s
inner join {{ ref("silver_products") }} as p on s.product_id = p.product_id
where not s.is_before_store_opening
