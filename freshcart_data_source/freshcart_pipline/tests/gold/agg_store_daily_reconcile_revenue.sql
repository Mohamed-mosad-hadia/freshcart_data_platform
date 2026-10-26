-- Reconciliation: net revenue per store in agg_store_daily must equal fct_orders
-- (local currency and USD), so no order is lost or double counted by the daily grid.
--
-- NOTE: We reference fct_orders by its resolved table name (not ref()) on purpose.
-- With Cosmos TestBehavior.AFTER_EACH, using ref("fct_orders") would make this test
-- run during fct_orders.test, BEFORE agg_store_daily is rebuilt — comparing fresh
-- fct_orders against stale agg_store_daily.  Dropping the ref() keeps this test
-- associated only with agg_store_daily, so it runs after both tables are current.
with
    agg as (
        select store_id, sum(net_revenue_local) as agg_local, sum(net_revenue_usd) as agg_usd
        from {{ ref("agg_store_daily") }}
        group by store_id
    ),
    fct as (
        select store_id, sum(net_revenue_local) as fct_local, sum(net_revenue_usd) as fct_usd
        from gold_sales.fct_orders
        group by store_id
    )

select f.store_id, a.agg_local, f.fct_local, a.agg_usd, f.fct_usd
from fct as f
left join agg as a on f.store_id = a.store_id
where abs(ifNull(a.agg_local, 0) - f.fct_local) > 1 or abs(ifNull(a.agg_usd, 0) - f.fct_usd) > 1
