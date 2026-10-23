select customer_id, first_name, last_name, email
from {{ ref("silver_customers") }}
where
    first_name = ''
    or last_name = ''
    or first_name != trim(first_name)
    or last_name != trim(last_name)
    or email != lower(email)
    or not match(email, '^[^@ ]+@[^@ ]+\\.[^@ ]+$')
