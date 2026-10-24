select order_id, order_status, placed_at, delivered_at
from {{ ref("silver_orders") }}
where
    (order_status = 'delivered' and delivered_at is null)
    or (order_status = 'cancelled' and delivered_at is not null)
    or delivered_at < placed_at
