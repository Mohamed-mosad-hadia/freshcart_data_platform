{{
    config(
        materialized="table",
        tags=["app", "silver", "payments"],
        schema="silver_app",
    )
}}

select
    payment_id,
    order_id,
    payment_method,
    payment_status,
    amount,
    case
        when payment_status = 'paid'
        then amount
        when payment_status = 'refunded'
        then - amount
    end as signed_amount,
    paid_at,
    order_id not in (select order_id from {{ ref("silver_orders") }}) as is_orphan,
    created_at,
    updated_at
from
    (
        select *
        from {{ source("bronze_app", "payments") }}
        where
            order_id not in (
                select order_id
                from {{ source("bronze_app", "orders") }}
                where customer_id = 150003
            )
        order by payment_id asc
        limit 1 by order_id, payment_status, payment_method, amount
    )
