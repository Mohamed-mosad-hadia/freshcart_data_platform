select customer_id, phone
from {{ ref("silver_customers") }}
where phone is not null and not match(phone, '^\\+[0-9]{10,15}$')
