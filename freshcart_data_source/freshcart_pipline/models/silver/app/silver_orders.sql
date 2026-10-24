{{
    config(
        materialized="table", tags=["app", "silver", "orders"], schema="silver_app"
    )
}}

select
    order_id,
    case
        when customer_id = 150001
        then 3
        when customer_id = 150002
        then 7
        else customer_id
    end as customer_id,
    store_id,
    order_status,
    placed_at,
    delivered_at,
    promo_code,
    created_at,
    updated_at
from
    (
        select *
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    )
where customer_id != 150003
