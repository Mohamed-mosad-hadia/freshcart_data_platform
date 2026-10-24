select order_id, payment_status, payment_method, amount, count() as n
from {{ ref("silver_payments") }}
group by order_id, payment_status, payment_method, amount
having count() > 1
