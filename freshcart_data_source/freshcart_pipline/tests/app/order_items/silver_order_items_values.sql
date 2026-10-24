select order_item_id, quantity, unit_price, line_amount
from {{ ref("silver_order_items") }}
where
    quantity not between 1
    and 3
    or unit_price <= 0
    or abs(line_amount - quantity * unit_price) > 0.005
