{{ config(materialized="table", tags=["gold", "core"], schema="gold_core") }}

-- SCD type 2: one row per product price version.
-- valid_from / valid_to are UTC timestamps; valid_to is NULL for the current price.
-- Price in effect for an order: placed_at >= valid_from and (placed_at < valid_to or valid_to is null)
select
    cityHash64(pp.product_id, pp.valid_from) as product_price_key,
    pp.product_id,
    p.product_name,
    p.category,
    pp.price_version,
    pp.unit_price_usd,
    pp.valid_from,
    pp.valid_to,
    pp.is_current
from {{ ref("silver_product_prices") }} as pp
inner join {{ ref("silver_products") }} as p on pp.product_id = p.product_id
