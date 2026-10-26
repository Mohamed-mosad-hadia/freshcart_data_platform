{{ config(materialized="table", tags=["gold", "core"], schema="gold_core") }}

-- One row per calendar day (Cairo), from the first FX rate (2023-01-01) to today.
-- Generated, not taken from orders, so days without orders or with only stock/FX data exist too.
with
    fx_days as (
        select distinct assumeNotNull(rate_date) as rate_date
        from {{ ref("silver_history") }}
        where is_latest_observation
    )

select
    toDate('2023-01-01') + number as date_day,
    toYear(date_day) as year,
    toQuarter(date_day) as quarter,
    toMonth(date_day) as month,
    dateName('month', date_day) as month_name,
    toStartOfMonth(date_day) as month_start,
    toStartOfWeek(date_day, 1) as week_start,  -- week starts on Monday
    toDayOfMonth(date_day) as day_of_month,
    toDayOfWeek(date_day) as day_of_week,  -- 1 = Monday ... 7 = Sunday
    dateName('weekday', date_day) as day_name,
    toDayOfWeek(date_day) in (5, 6) as is_weekend,  -- Friday, Saturday (Egypt / KSA / UAE retail week)
    date_day in (select rate_date from fx_days) as is_fx_business_day  -- FX rate published that day
from numbers(toUInt32(dateDiff('day', toDate('2023-01-01'), toDate(now('Africa/Cairo'))) + 1))
