select
    s.store_id,
    s.store_name,
    s.city,
    s.country,
    s.currency,
    s.opened_at,
    s.created_at,
    s.updated_at,
    o.first_order,
    o.orders,
    s.opened_at > todate(o.first_order) as opened_after_first_order
from {{ source("bronze_app", "stores") }} s
left join
    (
        select store_id, min(placed_at) as first_order, count() as orders
        from {{ source("bronze_app", "orders") }}
        group by store_id
    ) o
    on s.store_id = o.store_id
order by s.store_id
