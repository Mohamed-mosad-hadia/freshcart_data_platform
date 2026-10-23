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

-- -------------------
select
    count() as customers,
    countif(first_name is null) as is_null,
    countif(trim(first_name) = '') as blank,
    countif(first_name != trim(first_name)) as untrimmed,
    countif(match(first_name, '[0-9]')) as has_digits,
    countif(match(first_name, '[^\\p{L} \\-\\.\']')) as odd_characters,
    countif(first_name = upper(first_name) and first_name != '') as all_caps,
    countif(first_name = lower(first_name) and first_name != '') as all_lower,
    min(length(first_name)) as min_len,
    max(length(first_name)) as max_len,
    grouparrayif(5)
    (first_name, match(first_name, '[^\\p{L} \\-\\.\']')) as odd_examples
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )

--
select customer_id, first_name, last_name
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
where first_name = upper(first_name) and first_name != ''

-- last name
select
    count() as customers,
    countif(last_name is null) as is_null,
    countif(trim(last_name) = '') as blank,
    countif(last_name != trim(last_name)) as untrimmed,
    countif(match(last_name, '[0-9]')) as has_digits,
    countif(match(last_name, '[^\\p{L} \\-\\.\']')) as odd_characters,
    countif(last_name = upper(last_name) and last_name != '') as all_caps,
    countif(last_name = lower(last_name) and last_name != '') as all_lower,
    min(length(last_name)) as min_len,
    max(length(last_name)) as max_len,
    grouparrayif(5)
    (last_name, match(last_name, '[^\\p{L} \\-\\.\']')) as odd_examples
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )

-- - checking Emails
select customer_id, first_name, last_name, email, signup_date
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
where
    lower(last_name) in ('tester', 'test')
    or lower(first_name) in ('qa', 'test')
    or lower(email) like '%test%'
    or lower(email) like '%@example.%'
limit 50

-- extracting all emails domain
select
    splitbychar('@', lower(trim(email)))[2] as domain,
    count() as customers,
    any(email) as example
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
group by domain
order by customers desc
limit 20

-- - phones
select
    replaceregexpall(phone, '[0-9]', '9') as phone_pattern,
    count() as customers,
    any(phone) as example
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
group by phone_pattern
order by customers desc
limit 20

select
    multiif(
        startswith(phone, '+20') or startswith(phone, '0020'),
        'EG +20',
        startswith(phone, '+966') or startswith(phone, '00966'),
        'SA +966',
        match(phone, '^0[0-9]{10}$'),
        'local 0xxxxxxxxxx',
        phone = '-',
        'missing',
        'other'
    ) as phone_kind,
    count() as customers,
    topk(3)
    (city) as top_cities
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
group by phone_kind
order by customers desc

select
    left(replaceall(phone, ' ', ''), 4) as prefix,
    length(phone) as bytes,
    count() as customers,
    any(phone) as example
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
where
    not (
        startswith(phone, '+20')
        or startswith(phone, '0020')
        or startswith(phone, '+966')
        or startswith(phone, '00966')
        or match(phone, '^0[0-9]{10}$')
    )
group by prefix, bytes
order by customers desc
limit 20

-- city
select
    lower(trim(city)) as city_key,
    uniqexact(city) as spellings,
    groupuniqarray(5)
    (city) as raw_values,
    count() as customers
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )
group by city_key
order by customers desc
limit 40

-- dates
select
    count() as customers,
    min(signup_date) as min_signup,
    max(signup_date) as max_signup,
    countif(signup_date = todate(0)) as signup_1970,
    countif(signup_date > today()) as signup_future,
    min(created_at) as min_created,
    max(created_at) as max_created,
    countif(updated_at < created_at) as updated_before_created,
    countif(todate(created_at) < signup_date) as created_before_signup,
    countif(todate(created_at) > signup_date) as created_after_signup
from
    (
        select *
        from {{ source("bronze_app", "customers") }}
        order by updated_at desc, created_at desc
        limit 1 by customer_id
    )

select customer_id, first_name, signup_date, created_at
from {{ source("bronze_app", "customers") }}
where todate(created_at) < signup_date
