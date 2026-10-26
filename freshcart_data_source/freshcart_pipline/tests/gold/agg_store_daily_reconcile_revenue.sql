-- Reconciliation: net revenue per store in agg_store_daily must equal fct_orders
-- (local currency and USD), so no order is lost or double counted by the daily grid.
with
    agg as (
        select store_id, sum(net_revenue_local) as agg_local, sum(net_revenue_usd) as agg_usd
        from {{ ref("agg_store_daily") }}
        group by store_id
    ),
    fct as (
        select store_id, sum(net_revenue_local) as fct_local, sum(net_revenue_usd) as fct_usd
        from {{ ref("fct_orders") }}
        group by store_id
    )

select f.store_id, a.agg_local, f.fct_local, a.agg_usd, f.fct_usd
from fct as f
left join agg as a on f.store_id = a.store_id
where abs(ifNull(a.agg_local, 0) - f.fct_local) > 1 or abs(ifNull(a.agg_usd, 0) - f.fct_usd) > 1
