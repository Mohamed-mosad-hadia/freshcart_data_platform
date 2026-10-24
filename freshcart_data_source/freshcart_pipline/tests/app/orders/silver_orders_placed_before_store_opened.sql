{{ config(severity="warn") }}

select o.order_id, o.store_id, o.placed_at, s.opened_at
from {{ ref("silver_orders") }} o
inner join {{ ref("silver_stores") }} s on o.store_id = s.store_id
where o.placed_at < s.opened_at
