{{ config(materialized="table", tags=["gold", "core", "fx"], schema="gold_core") }}

-- One rate per calendar day and currency (units of currency per 1 USD).
-- The provider publishes Sunday to Thursday only: Friday, Saturday and days not yet
-- published take the last published rate (ASOF JOIN = latest rate_date <= date_day).
-- Convert: amount_usd = amount_local / rate_per_usd
with
    calendar as (select date_day from {{ ref("dim_date") }}),

    currencies as (
        select distinct assumeNotNull(quote_currency) as currency
        from {{ ref("silver_history") }}
        where is_latest_observation
    ),

    published as (
        select
            assumeNotNull(quote_currency) as currency,
            assumeNotNull(rate_date) as rate_date,
            exchange_rate
        from {{ ref("silver_history") }}
        where is_latest_observation and not has_unusable_exchange_rate
    ),

    grid as (
        select c.date_day, cur.currency
        from calendar as c
        cross join currencies as cur
    ),

    filled as (
        select
            g.date_day,
            g.currency,
            p.exchange_rate as rate_per_usd,
            p.rate_date as source_rate_date
        from grid as g
        asof left join published as p
            on g.currency = p.currency
            and g.date_day >= p.rate_date
    )

select
    date_day,
    currency,
    rate_per_usd,
    source_rate_date,
    date_day != source_rate_date as is_carried_forward
from filled

union all

-- USD itself, so USD amounts can use the same join
select
    date_day,
    'USD' as currency,
    toDecimal64(1, 8) as rate_per_usd,
    date_day as source_rate_date,
    false as is_carried_forward
from calendar
