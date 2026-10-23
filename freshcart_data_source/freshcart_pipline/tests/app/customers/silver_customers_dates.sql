select customer_id, signup_date, created_at, updated_at
from {{ ref("silver_customers") }}
where signup_date > today() or signup_date = '1970-01-01' or updated_at < created_at
