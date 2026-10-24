-- overview
select
    count() as total_rows,
    uniqExact(product_id) as distinct_products,
    uniqExact(product_id, valid_from) as distinct_product_valid_from,
    min(valid_from) as min_valid_from,
    max(valid_from) as max_valid_from
from {{ source("bronze_app", "product_prices") }}

-- rows per product (how many price versions?)
select versions, count() as products
from
    (
        select product_id, count() as versions
        from {{ source("bronze_app", "product_prices") }}
        group by product_id
    )
group by versions
order by versions

-- exact duplicates (same product, same valid_from, same price)
select
    product_id,
    valid_from,
    unit_price_usd,
    count() as copies,
    groupArray(created_at) as created_list,
    groupArray(updated_at) as updated_list
from {{ source("bronze_app", "product_prices") }}
group by product_id, valid_from, unit_price_usd
having copies > 1
order by copies desc
limit 20

-- conflicts: same product and valid_from but different prices
select
    product_id,
    valid_from,
    uniqExact(unit_price_usd) as prices,
    groupArray(unit_price_usd) as price_list,
    groupArray(updated_at) as updated_list
from {{ source("bronze_app", "product_prices") }}
group by product_id, valid_from
having prices > 1
limit 20

-- product_id: nulls, orphans, products without any price row
select
    countIf(product_id is null) as is_null,
    uniqExactIf(
        product_id,
        product_id not in (select product_id from {{ source("bronze_app", "products") }})
    ) as orphan_product_ids,
    (
        select count()
        from {{ source("bronze_app", "products") }}
        where
            product_id
            not in (select product_id from {{ source("bronze_app", "product_prices") }})
    ) as products_without_price
from {{ source("bronze_app", "product_prices") }}

-- unit_price_usd
select
    count() as total_rows,
    countIf(unit_price_usd is null) as is_null,
    countIf(unit_price_usd <= 0) as non_positive,
    min(unit_price_usd) as min_price,
    max(unit_price_usd) as max_price,
    round(avg(unit_price_usd), 2) as avg_price
from {{ source("bronze_app", "product_prices") }}

-- price change between consecutive versions of the same product
select
    product_id,
    valid_from,
    prev_price,
    unit_price_usd,
    round((unit_price_usd - prev_price) / prev_price * 100, 2) as pct_change
from
    (
        select
            product_id,
            valid_from,
            unit_price_usd,
            lagInFrame(unit_price_usd) over (
                partition by product_id
                order by valid_from
                rows between 1 preceding and current row
            ) as prev_price,
            row_number() over (partition by product_id order by valid_from) as rn
        from {{ source("bronze_app", "product_prices") }}
    )
where rn > 1
order by abs(pct_change) desc
limit 20

-- versions that do not change the price (same price as the previous version)
select count() as no_change_versions
from
    (
        select
            unit_price_usd,
            lagInFrame(unit_price_usd) over (
                partition by product_id
                order by valid_from
                rows between 1 preceding and current row
            ) as prev_price,
            row_number() over (partition by product_id order by valid_from) as rn
        from {{ source("bronze_app", "product_prices") }}
    )
where rn > 1 and unit_price_usd = prev_price

-- valid_from / created_at / updated_at
select
    countIf(valid_from > now()) as valid_from_future,
    countIf(updated_at < created_at) as updated_before_created,
    countIf(updated_at != created_at) as changed_after_insert,
    countIf(toDate(valid_from) != toDate(created_at)) as valid_from_differs_from_created,
    min(created_at) as min_created,
    max(created_at) as max_created,
    min(updated_at) as min_updated,
    max(updated_at) as max_updated
from {{ source("bronze_app", "product_prices") }}

-- first price starts before the product existed?
select
    h.product_id,
    min(h.valid_from) as first_valid_from,
    any(p.created_at) as product_created_at
from {{ source("bronze_app", "product_prices") }} as h
inner join
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) as p
    using product_id
group by h.product_id
having first_valid_from < product_created_at
limit 20

-- latest price in history vs current catalogue price
select
    count() as compared,
    countIf(p.unit_price_usd != h.unit_price_usd) as price_mismatch
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) as p
inner join
    (
        select *
        from {{ source("bronze_app", "product_prices") }}
        order by valid_from desc, updated_at desc
        limit 1 by product_id
    ) as h
    using product_id

-- sample: full history of a few products that changed price
select product_id, valid_from, unit_price_usd, created_at, updated_at
from {{ source("bronze_app", "product_prices") }}
where product_id in (13, 64, 115)
order by product_id, valid_from
