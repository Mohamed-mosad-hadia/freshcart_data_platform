{{
    config(
        materialized="table", tags=["app", "silver", "customers"], schema="silver_app"
    )
}}

select
    customer_id,
    trim(first_name) as first_name,
    trim(last_name) as last_name,
    lower(trim(email)) as email,
    case
        when not match(phone, '[0-9]')
        then null
        when phone_nospace like '+%'
        then phone_nospace
        when phone_nospace like '00%'
        then concat('+', substring(phone_nospace, 3))
        when match(phone, '^0[0-9]{10}$')
        then concat('+20', substring(phone, 2))
    end as phone,
    trim(city) as city,
    signup_date,
    created_at,
    updated_at
from
    (
        select *
        from
            (
                select *, replace(phone, ' ', '') as phone_nospace
                from {{ source("bronze_app", "customers") }}
                order by updated_at desc, created_at desc
                limit 1 by customer_id
            )
        order by customer_id asc
        limit 1 by lower(trim(email))
    )
where lower(trim(email)) not like '%@test.freshcart.com'
