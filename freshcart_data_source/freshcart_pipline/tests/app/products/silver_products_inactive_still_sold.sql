-- Known issue: deactivated products keep appearing in new orders.
-- Warn (do not fail) so the problem stays visible without stopping the pipeline.
{{ config(severity="warn") }}

select
    p.product_id,
    p.product_name,
    p.updated_at as deactivated_at,
    count() as lines_after_deactivation,
    max(oi.created_at) as last_sold_at
from {{ ref("silver_products") }} as p
inner join {{ ref("silver_order_items") }} as oi on oi.product_id = p.product_id
where not p.is_active and oi.created_at > p.updated_at
group by p.product_id, p.product_name, p.updated_at
