-- overview
select
    count() as total_rows,
    uniqExact(product_id) as distinct_products,
    count() - uniqExact(product_id) as extra_versions
from {{ source("bronze_app", "products") }}

-- duplicated ids: which columns change between versions?
select
    product_id,
    count() as versions,
    uniqExact(product_name) as names,
    uniqExact(category) as categories,
    uniqExact(unit_price_usd) as prices,
    uniqExact(is_active) as active_flags,
    uniqExact(updated_at) as updated_ats,
    groupArray(unit_price_usd) as price_list,
    groupArray(updated_at) as updated_list
from {{ source("bronze_app", "products") }}
group by product_id
having versions > 1
order by versions desc
limit 20

-- product_id
select
    count() as products,
    countIf(product_id is null) as is_null,
    countIf(product_id <= 0) as non_positive,
    min(product_id) as min_id,
    max(product_id) as max_id,
    max(product_id) - min(product_id) + 1 - count() as gaps_in_range
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )

-- product_name
select
    count() as products,
    countIf(product_name is null) as is_null,
    countIf(trim(product_name) = '') as blank,
    countIf(product_name != trim(product_name)) as untrimmed,
    countIf(match(product_name, '\\s{2,}')) as double_spaces,
    countIf(product_name = upper(product_name)) as all_caps,
    countIf(product_name = lower(product_name)) as all_lower,
    min(length(product_name)) as min_len,
    max(length(product_name)) as max_len,
    groupArrayIf(5)
    (product_name, match(product_name, '[^\\p{L}0-9 \\-\\.\'&%(),/]')) as odd_examples
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )

-- same name used by more than one product_id?
select
    lower(trim(product_name)) as name_key,
    count() as ids,
    groupArray(product_id) as product_ids
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )
group by name_key
having ids > 1

-- size suffix at the end of the name (500g, 1kg, 1L, 6-pack ...)
select
    extract(product_name, '(\\S+)$') as size_token,
    count() as products,
    groupArray(3)(product_name) as examples
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )
group by size_token
order by products desc

-- category: spelling variants (all versions)
select
    lower(trim(category)) as category_key,
    uniqExact(category) as spellings,
    groupUniqArray(category) as raw_values
from {{ source("bronze_app", "products") }}
group by category_key
order by category_key

-- category: products per category
select
    category,
    count() as products,
    countIf(is_active) as active_products
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )
group by category
order by category

-- unit_price_usd
select
    count() as products,
    countIf(unit_price_usd is null) as is_null,
    countIf(unit_price_usd <= 0) as non_positive,
    min(unit_price_usd) as min_price,
    max(unit_price_usd) as max_price,
    round(avg(unit_price_usd), 2) as avg_price,
    quantileExact(0.5)(unit_price_usd) as median_price
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )

-- price change between versions (% change)
select
    product_id,
    argMin(unit_price_usd, updated_at) as old_price,
    argMax(unit_price_usd, updated_at) as new_price,
    round((new_price - old_price) / old_price * 100, 2) as pct_change
from {{ source("bronze_app", "products") }}
group by product_id
having count() > 1
order by pct_change desc

-- catalogue price vs latest row in product_prices
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
        order by valid_from desc
        limit 1 by product_id
    ) as h
    using product_id

-- is_active
select is_active, count() as products
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    )
group by is_active

-- inactive products that still appear in orders after their last update
select
    p.product_id,
    p.product_name,
    p.updated_at,
    count() as lines_after_update,
    max(o.created_at) as last_sold
from
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) as p
inner join {{ source("bronze_app", "order_items") }} as o using product_id
where not p.is_active and o.created_at > p.updated_at
group by p.product_id, p.product_name, p.updated_at
order by p.product_id

-- created_at / updated_at
select
    count() as total_rows,
    min(created_at) as min_created,
    max(created_at) as max_created,
    min(updated_at) as min_updated,
    max(updated_at) as max_updated,
    countIf(updated_at < created_at) as updated_before_created,
    countIf(created_at > now()) as created_in_future,
    countIf(updated_at > now()) as updated_in_future
from {{ source("bronze_app", "products") }}

-- referential: products sold but missing from the catalogue
select
    uniqExact(product_id) as sold_product_ids,
    uniqExactIf(
        product_id,
        product_id not in (select product_id from {{ source("bronze_app", "products") }})
    ) as missing_from_products
from {{ source("bronze_app", "order_items") }}
