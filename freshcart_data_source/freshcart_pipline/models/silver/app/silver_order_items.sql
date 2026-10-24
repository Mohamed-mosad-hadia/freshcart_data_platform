{{
    config(
        materialized="table",
        unique_key="order_item_id",
        tags=["app", "silver", "order_items"],
        schema="silver_app",
    )
}}

select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    line_amount,
    order_id not in (select order_id from {{ ref("silver_orders") }}) as is_orphan,
    created_at,
    updated_at
from {{ source("bronze_app", "order_items") }}
where
    order_id not in (
        select order_id
        from {{ source("bronze_app", "orders") }}
        where customer_id = 150003
    )

    /*
    {% if is_incremental() %}
        and updated_at > (select max(updated_at) from {{ this }})
    {% endif %}
*/
