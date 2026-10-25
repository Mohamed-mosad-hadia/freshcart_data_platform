-- Completeness: the FX provider publishes every business day (Sunday to Thursday).
-- Every business day between the first and last rate_date must exist in silver_history,
-- with all three quote currencies. (FX postmortem 2026-10-23, action item 6)
with
    days as (
        select rate_date, uniqExact(quote_currency) as currencies
        from {{ ref("silver_history") }}
        where is_latest_observation
        group by rate_date
    ),
    bounds as (
        select
            assumeNotNull(min(rate_date)) as first_day,
            assumeNotNull(max(rate_date)) as last_day
        from days
    ),
    calendar as (
        select addDays(first_day, day_offset) as cal_date
        from bounds
        array join range(toUInt32(dateDiff('day', first_day, last_day)) + 1) as day_offset
    )

select cal_date as rate_date, 'missing business day' as problem
from calendar
where
    toDayOfWeek(cal_date) not in (5, 6)  -- 5 = Friday, 6 = Saturday
    and cal_date not in (select rate_date from days)

union all

select rate_date, 'missing currency' as problem
from days
where currencies < 3
