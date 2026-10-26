{{ config(materialized="table", tags=["gold", "sales"], schema="gold_sales") }}

-- One row per order. Day = Cairo business day of placed_at.
-- Net revenue = order lines of DELIVERED orders minus refunds on those orders
-- (cancelled / open orders = 0; refunds on cancelled orders only affect cash, see fct_payments).
-- USD = local / rate_per_usd of the order day (weekends use the last published rate).
with
    items as (
        select
            order_id,
            count() as item_lines,
            sum(quantity) as items_quantity,
            sum(line_amount) as order_amount_local
        from {{ ref("silver_order_items") }}
        group by order_id
    ),

    refunds as (
        select order_id, sum(amount) as refunded_amount_local
        from {{ ref("silver_payments") }}
        where payment_status = 'refunded'
        group by order_id
    ),

    orders as (
        -- explicit aliases: ClickHouse names a joined column 'o.order_id' when another
        -- joined table has the same column name
        select
            o.order_id as order_id,
            o.customer_id as customer_id,
            o.store_id as store_id,
            st.currency as currency,
            toDate(o.placed_at, 'Africa/Cairo') as order_date,
            o.placed_at as placed_at,
            o.delivered_at as delivered_at,
            o.order_status as order_status,
            o.order_status = 'delivered' as is_delivered,
            o.promo_code as promo_code,
            ifNull(i.item_lines, 0) as item_lines,
            ifNull(i.items_quantity, 0) as items_quantity,
            ifNull(toFloat64(i.order_amount_local), 0) as order_amount_local,
            ifNull(toFloat64(r.refunded_amount_local), 0) as refunded_amount_local
        from {{ ref("silver_orders") }} as o
        inner join {{ ref("silver_stores") }} as st on o.store_id = st.store_id
        left join items as i on o.order_id = i.order_id
        left join refunds as r on o.order_id = r.order_id
    )

select
    o.order_id as order_id,
    o.customer_id as customer_id,
    o.store_id as store_id,
    o.currency as currency,
    o.order_date as order_date,
    o.placed_at as placed_at,
    o.delivered_at as delivered_at,
    o.order_status as order_status,
    o.is_delivered as is_delivered,
    o.promo_code as promo_code,
    o.item_lines as item_lines,
    o.items_quantity as items_quantity,
    -- local currency
    round(o.order_amount_local, 2) as order_amount_local,
    round(if(o.is_delivered, o.refunded_amount_local, 0), 2) as refunded_amount_local,
    round(if(o.is_delivered, o.order_amount_local - o.refunded_amount_local, 0), 2) as net_revenue_local,
    -- USD
    toFloat64(fx.rate_per_usd) as rate_per_usd,
    round(o.order_amount_local / rate_per_usd, 2) as order_amount_usd,
    round(net_revenue_local / rate_per_usd, 2) as net_revenue_usd,
    -- delivery time (delivered orders only)
    if(
        o.is_delivered and o.delivered_at is not null,
        dateDiff('minute', o.placed_at, o.delivered_at),
        null
    ) as delivery_minutes
from orders as o
left join {{ ref("fct_fx_rates_daily") }} as fx
    on fx.date_day = o.order_date
    and fx.currency = o.currency
