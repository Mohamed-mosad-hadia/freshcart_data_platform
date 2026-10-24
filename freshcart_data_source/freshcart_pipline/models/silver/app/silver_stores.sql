{{
    config(
        materialized="table", tags=["app", "silver", "stores"], schema="silver_app"
    )
}}

select
    store_id,
    trim(store_name) as store_name,
    trim(city) as city,
    upper(trim(country)) as country,
    upper(trim(currency)) as currency,
    opened_at,
    created_at,
    updated_at
from
    (
        select *
        from {{ source("bronze_app", "stores") }}
        order by updated_at desc, created_at desc
        limit 1 by store_id
    )
