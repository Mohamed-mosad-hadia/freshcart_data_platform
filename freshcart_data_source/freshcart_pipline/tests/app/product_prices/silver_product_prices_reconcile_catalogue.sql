-- Reconciliation: the current price in the history must equal the catalogue price
select
    p.product_id,
    p.unit_price_usd as catalogue_price,
    h.unit_price_usd as current_history_price
from {{ ref("silver_products") }} as p
left join
    (select * from {{ ref("silver_product_prices") }} where is_current) as h
    on h.product_id = p.product_id
where h.product_id = 0 or h.unit_price_usd != p.unit_price_usd
