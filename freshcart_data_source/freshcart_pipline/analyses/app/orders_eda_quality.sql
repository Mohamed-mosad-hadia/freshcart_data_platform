select
    count() as raw_rows,
    count(distinct order_id) as distinct_orders,
    count() - count(distinct order_id) as extra_rows,
    min(order_id) as min_id,
    max(order_id) as max_id,
    max(order_id) - min(order_id) + 1 - count(distinct order_id) as gaps_in_id_range,
    sum(order_id <= 0) as not_positive,
    (
        select count()
        from
            (
                select order_id
                from {{ source("bronze_app", "orders") }}
                group by order_id
                having count(distinct tuple(customer_id, store_id, placed_at)) > 1
            )
    ) as ids_where_customer_store_or_placed_differ,
    (
        select count()
        from
            (
                select order_id
                from {{ source("bronze_app", "orders") }}
                group by order_id
                having count(distinct tuple(order_status)) > 1
            )
    ) as ids_where_status_differs,
    (
        select count()
        from
            (
                select order_id
                from {{ source("bronze_app", "orders") }}
                group by order_id
                having count(distinct tuple(created_at)) > 1
            )
    ) as ids_where_created_at_differs
from {{ source("bronze_app", "orders") }}

-- ---Customer_id 
select
    count() as orders,
    count(distinct customer_id) as distinct_customers,
    min(customer_id) as min_id,
    max(customer_id) as max_id,
    sum(customer_id <= 0) as not_positive,
    sum(customer_id in (150001, 150002)) as orders_of_duplicate_customers,
    sum(customer_id = 150003) as orders_of_test_customer,
    sum(
        customer_id
        not in (select customer_id from {{ source("bronze_app", "customers") }})
    ) as orphan_customer_ids,
    max(customer_orders) as max_orders_one_customer
from
    (
        select *, count() over (partition by customer_id) as customer_orders
        from
            (
                select *
                from {{ source("bronze_app", "orders") }}
                order by updated_at desc, created_at desc
                limit 1 by order_id
            )
    )

-- -order_status
select
    concat('[', order_status, ']') as status,
    count() as orders,
    round(100 * count() / sum(count()) over (), 2) as pct,
    sum(delivered_at is null) as delivered_at_null,
    sum(delivered_at is not null) as delivered_at_set
from
    (
        select *
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    )
group by order_status
order by orders desc

-- -----store_id
select
    count() as orders,
    count(distinct store_id) as distinct_stores,
    min(store_id) as min_id,
    max(store_id) as max_id,
    sum(store_id <= 0) as not_positive,
    sum(
        store_id not in (select store_id from {{ source("bronze_app", "stores") }})
    ) as orphan_store_ids,
    (
        select count() from {{ source("bronze_app", "stores") }}
    ) as stores_in_stores_table,
    min(store_orders) as min_orders_one_store,
    max(store_orders) as max_orders_one_store
from
    (
        select *, count() over (partition by store_id) as store_orders
        from
            (
                select *
                from {{ source("bronze_app", "orders") }}
                order by updated_at desc, created_at desc
                limit 1 by order_id
            )
    )

-- - placed_at
select
    count() as orders,
    min(o.placed_at) as min_placed,
    max(o.placed_at) as max_placed,
    sum(o.placed_at < '2000-01-01') as default_or_before_2000,
    sum(o.placed_at > now()) as in_future,
    sum(o.placed_at < s.opened_at) as before_store_opened,
    sum(o.placed_at < c.signup_date) as before_customer_signup,
    sum(o.updated_at < o.placed_at) as updated_before_placed,
    sum(o.created_at < o.placed_at) as created_before_placed
from
    (
        select *
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    ) o
inner join {{ source("bronze_app", "stores") }} s on o.store_id = s.store_id
inner join
    (
        select customer_id, signup_date
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    ) c
    on o.customer_id = c.customer_id

select
    s.store_id,
    s.store_name,
    s.opened_at,
    min(o.placed_at) as first_order,
    count() as orders,
    sum(o.placed_at < s.opened_at) as before_opening,
    max(o.placed_at < s.opened_at ? o.placed_at:null) as last_order_before_opening
from
    (
        select *
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    ) o
inner join {{ source("bronze_app", "stores") }} s on o.store_id = s.store_id
group by s.store_id, s.store_name, s.opened_at
order by s.store_id

-- ---delivered_at
select
    count() as delivered_orders,
    sum(delivered_at < placed_at) as delivered_before_placed,
    sum(delivered_at > now()) as delivered_in_future,
    sum(updated_at < delivered_at) as updated_before_delivered,
    sum(date_diff('minute', placed_at, delivered_at) < 5) as under_5_min,
    sum(date_diff('minute', placed_at, delivered_at) > 1440) as over_24_hours,
    min(date_diff('minute', placed_at, delivered_at)) as min_minutes,
    quantile(0.5)
    (date_diff('minute', placed_at, delivered_at)) as median_minutes,
    quantile(0.95)
    (date_diff('minute', placed_at, delivered_at)) as p95_minutes,
    quantile(0.999)
    (date_diff('minute', placed_at, delivered_at)) as p999_minutes,
    max(date_diff('minute', placed_at, delivered_at)) as max_minutes
from
    (
        select *
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    )
where delivered_at is not null

-- --- promo_code
select
    concat('[', coalesce(promo_code, '<NULL>'), ']') as promo,
    count() as orders,
    round(100 * count() / sum(count()) over (), 2) as pct,
    sum(order_status = 'cancelled') as cancelled
from
    (
        select *
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    )
group by promo_code
order by orders desc
limit 20
