{{
    config(
        materialized="table", tags=["app", "silver", "products"], schema="silver_app"
    )
}}

select
    product_id,
    product_name,
    extract(product_name, '(\\S+)$') as size_label,
    category,
    unit_price_usd,
    is_active,
    created_at,
    updated_at
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )
