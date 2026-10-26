{{ config(materialized="table", tags=["gold", "sales"], schema="gold_sales") }}

-- One row per payment or refund. Cash day = Cairo business day of paid_at
-- (refunds count on the day they happen, whatever the order status).
-- Payments whose order is not loaded yet (late-arriving, is_orphan) are left out
-- until the next night, because their store is unknown.
with
    payments as (
        -- explicit aliases: ClickHouse names a joined column 'o.store_id' when another
        -- joined table has the same column name
        select
            p.payment_id as payment_id,
            p.order_id as order_id,
            o.customer_id as customer_id,
            o.store_id as store_id,
            st.currency as currency,
            o.order_status as order_status,
            toDate(p.paid_at, 'Africa/Cairo') as payment_date,
            p.paid_at as paid_at,
            p.payment_method as payment_method,
            p.payment_status as payment_status,
            toFloat64(p.amount) as amount_local,
            toFloat64(p.signed_amount) as signed_amount_local
        from {{ ref("silver_payments") }} as p
        inner join {{ ref("silver_orders") }} as o on p.order_id = o.order_id
        inner join {{ ref("silver_stores") }} as st on o.store_id = st.store_id
    )

select
    p.payment_id as payment_id,
    p.order_id as order_id,
    p.customer_id as customer_id,
    p.store_id as store_id,
    p.currency as currency,
    p.order_status as order_status,
    p.payment_date as payment_date,
    p.paid_at as paid_at,
    p.payment_method as payment_method,
    p.payment_status as payment_status,
    round(p.amount_local, 2) as amount_local,
    round(p.signed_amount_local, 2) as signed_amount_local,
    toFloat64(fx.rate_per_usd) as rate_per_usd,
    round(p.signed_amount_local / rate_per_usd, 2) as signed_amount_usd
from payments as p
left join {{ ref("fct_fx_rates_daily") }} as fx
    on fx.date_day = p.payment_date
    and fx.currency = p.currency
