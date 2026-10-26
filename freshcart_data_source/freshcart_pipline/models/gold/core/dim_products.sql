{{ config(materialized="table", tags=["gold", "core"], schema="gold_core") }}

-- Current product attributes (type 1). Price history is in dim_product_price_history.
-- supplier comes from the stock files: each product is supplied by exactly one supplier.
with
    product_supplier as (
        select product_id, any(supplier) as supplier
        from {{ ref("silver_supplier_stock") }}
        group by product_id
    )

select
    p.product_id,
    p.product_name,
    p.size_label,
    p.category,
    s.supplier,
    p.unit_price_usd as current_unit_price_usd,
    p.is_active
from {{ ref("silver_products") }} as p
left join product_supplier as s on p.product_id = s.product_id
