{{ config(materialized="table", tags=["gold", "sales"], schema="gold_sales") }}

-- One row per store and Cairo day, from the store's first activity (opening day, or an
-- earlier order / payment: some orders exist before the official opening date) to today.
-- Answers: net revenue and cash collected per store and day in local currency and USD,
-- number of orders, average basket, delivery time, unique customers.
with
    first_activity as (
        select store_id, min(activity_day) as first_day
        from
            (
                select store_id, opened_on as activity_day from {{ ref("dim_stores") }}
                union all
                select store_id, order_date from {{ ref("fct_orders") }}
                union all
                select store_id, payment_date from {{ ref("fct_payments") }}
            )
        group by store_id
    ),

    grid as (
        select
            d.date_day as date_day,
            s.store_id as store_id,
            s.store_name as store_name,
            s.currency as currency
        from {{ ref("dim_date") }} as d
        cross join {{ ref("dim_stores") }} as s
        inner join first_activity as f on s.store_id = f.store_id
        where d.date_day >= f.first_day
    ),

    orders_daily as (
        select
            store_id,
            order_date,
            count() as orders_placed,
            countIf(is_delivered) as orders_delivered,
            countIf(order_status = 'cancelled') as orders_cancelled,
            uniqExact(customer_id) as unique_customers,
            sum(net_revenue_local) as net_revenue_local,
            sum(net_revenue_usd) as net_revenue_usd,
            avgIfOrNull(order_amount_local, is_delivered) as avg_basket_local,
            avgIfOrNull(order_amount_usd, is_delivered) as avg_basket_usd,
            avgIfOrNull(delivery_minutes, is_delivered) as avg_delivery_minutes
        from {{ ref("fct_orders") }}
        group by store_id, order_date
    ),

    cash_daily as (
        select
            store_id,
            payment_date,
            sumIf(amount_local, payment_status = 'paid') as cash_in_local,
            sumIf(amount_local, payment_status = 'refunded') as refunds_out_local,
            sum(signed_amount_local) as cash_collected_local,
            sum(signed_amount_usd) as cash_collected_usd
        from {{ ref("fct_payments") }}
        group by store_id, payment_date
    )

select
    g.date_day as date_day,
    g.store_id as store_id,
    g.store_name as store_name,
    g.currency as currency,
    o.orders_placed as orders_placed,
    o.orders_delivered as orders_delivered,
    o.orders_cancelled as orders_cancelled,
    o.unique_customers as unique_customers,
    round(o.net_revenue_local, 2) as net_revenue_local,
    round(o.net_revenue_usd, 2) as net_revenue_usd,
    round(c.cash_in_local, 2) as cash_in_local,
    round(c.refunds_out_local, 2) as refunds_out_local,
    round(c.cash_collected_local, 2) as cash_collected_local,
    round(c.cash_collected_usd, 2) as cash_collected_usd,
    round(o.avg_basket_local, 2) as avg_basket_local,
    round(o.avg_basket_usd, 2) as avg_basket_usd,
    round(o.avg_delivery_minutes, 1) as avg_delivery_minutes
from grid as g
left join orders_daily as o on g.store_id = o.store_id and g.date_day = o.order_date
left join cash_daily as c on g.store_id = c.store_id and g.date_day = c.payment_date
