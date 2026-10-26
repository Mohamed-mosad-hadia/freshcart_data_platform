-- Reconciliation: cash collected per store in agg_store_daily must equal fct_payments
--
-- NOTE: We reference fct_payments by its resolved table name (not ref()) on purpose.
-- With Cosmos TestBehavior.AFTER_EACH, using ref("fct_payments") would make this test
-- run during fct_payments.test, BEFORE agg_store_daily is rebuilt — comparing fresh
-- fct_payments against stale agg_store_daily.  Dropping the ref() keeps this test
-- associated only with agg_store_daily, so it runs after both tables are current.
with
    agg as (
        select store_id, sum(cash_collected_local) as agg_local
        from {{ ref("agg_store_daily") }}
        group by store_id
    ),
    fct as (
        select store_id, sum(signed_amount_local) as fct_local
        from gold_sales.fct_payments
        group by store_id
    )

select f.store_id, a.agg_local, f.fct_local
from fct as f
left join agg as a on f.store_id = a.store_id
where abs(ifNull(a.agg_local, 0) - f.fct_local) > 1
