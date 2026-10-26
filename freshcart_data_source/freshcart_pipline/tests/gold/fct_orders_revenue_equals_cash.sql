-- Reconciliation (two ways of computing the same number):
-- for a delivered order, net revenue (order lines - refunds) must equal the cash
-- collected for it (payments - refunds). Warn: a business exception (partial payment,
-- payment not loaded yet) is possible and must be looked at, not block the pipeline.
{{ config(severity="warn") }}

with
    cash as (
        select order_id, sum(signed_amount_local) as cash_local
        from {{ ref("fct_payments") }}
        group by order_id
    )

select
    o.order_id,
    o.store_id,
    o.order_date,
    o.net_revenue_local,
    c.cash_local
from {{ ref("fct_orders") }} as o
inner join cash as c on o.order_id = c.order_id
where o.is_delivered and abs(o.net_revenue_local - c.cash_local) > 0.01
