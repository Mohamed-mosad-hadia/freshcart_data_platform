select *
from {{ source("bronze_app", "customers") }}
where
    customer_id in (
        select customer_id
        from {{ source("bronze_app", "customers") }}
        group by customer_id
        having count(*) > 1
    )
order by customer_id, updated_at
;

-- there's duplicates in customers table 
