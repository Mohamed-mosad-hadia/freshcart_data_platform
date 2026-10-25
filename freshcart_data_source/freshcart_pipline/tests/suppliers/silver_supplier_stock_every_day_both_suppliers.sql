-- Completeness: every day between the first and last stock_date has both supplier files
with
    days as (
        select stock_date, uniqExact(supplier) as suppliers
        from {{ ref("silver_supplier_stock") }}
        group by stock_date
    ),
    bounds as (
        select
            assumeNotNull(min(stock_date)) as first_day,
            assumeNotNull(max(stock_date)) as last_day
        from days
    ),
    calendar as (
        select addDays(first_day, day_offset) as cal_date
        from bounds
        array join range(toUInt32(dateDiff('day', first_day, last_day)) + 1) as day_offset
    )

select c.cal_date as stock_date, ifNull(d.suppliers, 0) as suppliers
from calendar as c
left join days as d on c.cal_date = d.stock_date
where ifNull(d.suppliers, 0) != 2
