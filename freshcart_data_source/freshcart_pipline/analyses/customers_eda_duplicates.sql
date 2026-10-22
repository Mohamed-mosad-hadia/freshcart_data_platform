select
    customer_id,
    count(*) as versions,
    min(updated_at) as first_seen,
    max(updated_at) as last_seen
from {{ source("bronze_app", "customers") }}
group by customer_id
having versions > 1
order by versions desc
limit 20
