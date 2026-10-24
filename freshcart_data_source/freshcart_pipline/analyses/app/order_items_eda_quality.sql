select
    count() as items,
    count(distinct order_item_id) as distinct_items,
    min(order_item_id) as min_id,
    max(order_item_id) as max_id,
    max(order_item_id)
    - min(order_item_id)
    + 1
    - count(distinct order_item_id) as gaps_in_id_range,
    sum(order_item_id <= 0) as item_id_not_positive,
    count(distinct order_id) as distinct_orders,
    sum(order_id <= 0) as order_id_not_positive,
    sum(
        order_id not in (select order_id from {{ source("bronze_app", "orders") }})
    ) as items_of_missing_orders,
    sum(
        order_id in (
            select order_id
            from {{ source("bronze_app", "orders") }}
            where customer_id = 150003
        )
    ) as items_of_qa_orders,
    max(items_in_order) as max_items_in_one_order,
    (
        select count()
        from
            (
                select order_id, product_id
                from {{ source("bronze_app", "order_items") }}
                group by order_id, product_id
                having count() > 1
            )
    ) as order_product_pairs_repeated
from
    (
        select *, count() over (partition by order_id) as items_in_order
        from {{ source("bronze_app", "order_items") }}
    )

-- -
select
    count() as repeated_pairs,
    sum(distinct_qty = 1 and distinct_price = 1) as identical_lines,
    sum(distinct_qty > 1) as different_quantity,
    sum(distinct_price > 1) as different_price,
    max(lines) as max_lines_same_product,
    min(order_id) as example_order,
    any(product_id) as example_product
from
    (
        select
            order_id,
            product_id,
            count() as lines,
            count(distinct quantity) as distinct_qty,
            count(distinct unit_price) as distinct_price
        from {{ source("bronze_app", "order_items") }}
        group by order_id, product_id
        having count() > 1
    )

select
    count() as orders_checked,
    sum(abs(paid - total_all) < 0.01) as payment_matches_all_lines,
    sum(abs(paid - total_dedup) < 0.01) as payment_matches_deduped,
    sum(
        abs(paid - total_all) >= 0.01 and abs(paid - total_dedup) >= 0.01
    ) as matches_neither
from
    (
        select
            i.order_id as order_id,
            sum(i.line_amount) as total_all,
            sum(if(i.rn = 1, i.line_amount, 0)) as total_dedup,
            any(p.paid) as paid
        from
            (
                select
                    *,
                    row_number() over (
                        partition by order_id, product_id, quantity, unit_price
                        order by order_item_id
                    ) as rn
                from {{ source("bronze_app", "order_items") }}
            ) i
        inner join
            (
                select order_id, sum(amount) as paid
                from {{ source("bronze_app", "payments") }}
                group by order_id
            ) p
            on i.order_id = p.order_id
        where
            i.order_id in (
                select order_id
                from {{ source("bronze_app", "order_items") }}
                group by order_id, product_id, quantity, unit_price
                having count() > 1
            )
            and i.order_id in (
                select order_id
                from {{ source("bronze_app", "orders") }}
                where promo_code is null and order_status = 'delivered'
            )
        group by i.order_id
    )

select
    p.n_payments as payments_per_order,
    p.min_status as min_payment_status,
    p.max_status as max_payment_status,
    count() as orders,
    round(avg(p.paid - i.total), 2) as avg_diff,
    min(p.paid - i.total) as min_diff,
    max(p.paid - i.total) as max_diff
from
    (
        select order_id, sum(line_amount) as total
        from {{ source("bronze_app", "order_items") }}
        group by order_id
    ) i
inner join
    (
        select
            order_id,
            sum(amount) as paid,
            count() as n_payments,
            min(payment_status) as min_status,
            max(payment_status) as max_status
        from {{ source("bronze_app", "payments") }}
        group by order_id
    ) p
    on i.order_id = p.order_id
where
    abs(p.paid - i.total) >= 0.01
    and i.order_id in (
        select order_id
        from {{ source("bronze_app", "orders") }}
        where promo_code is null and order_status = 'delivered'
    )
group by payments_per_order, min_payment_status, max_payment_status
order by orders desc

select
    count() as items,
    count(distinct product_id) as distinct_products,
    sum(product_id <= 0) as product_not_positive,
    sum(
        product_id
        not in (select product_id from {{ source("bronze_app", "products") }})
    ) as orphan_products,
    min(quantity) as min_qty,
    max(quantity) as max_qty,
    sum(quantity <= 0) as qty_not_positive,
    min(unit_price) as min_price,
    max(unit_price) as max_price,
    sum(unit_price <= 0) as price_not_positive,
    sum(abs(line_amount - quantity * unit_price) > 0.005) as line_amount_mismatch,
    sum(updated_at < created_at) as updated_before_created
from {{ source("bronze_app", "order_items") }}

select
    s.currency as currency,
    count() as items,
    round(avg((i.unit_price * 1.0) / p.unit_price_usd), 3) as avg_ratio,
    round(min((i.unit_price * 1.0) / p.unit_price_usd), 3) as min_ratio,
    round(max((i.unit_price * 1.0) / p.unit_price_usd), 3) as max_ratio
from {{ source("bronze_app", "order_items") }} i
inner join
    (
        select order_id, store_id
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    ) o
    on i.order_id = o.order_id
inner join {{ source("bronze_app", "stores") }} s on o.store_id = s.store_id
inner join
    (
        select product_id, unit_price_usd
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) p
    on i.product_id = p.product_id
group by currency
order by items desc

select
    date_trunc('quarter', o.placed_at) as qtr,
    s.currency as currency,
    count() as items,
    round(avg((i.unit_price * 1.0) / p.unit_price_usd), 3) as avg_ratio
from {{ source("bronze_app", "order_items") }} i
inner join
    (
        select order_id, store_id, placed_at
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    ) o
    on i.order_id = o.order_id
inner join {{ source("bronze_app", "stores") }} s on o.store_id = s.store_id
inner join
    (
        select product_id, unit_price_usd
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) p
    on i.product_id = p.product_id
where s.currency in ('SAR', 'AED')
group by qtr, currency
order by currency, qtr

select
    s.currency as currency,
    date_trunc('quarter', o.placed_at) as qtr,
    count() as items,
    round(avg((i.unit_price * 1.0) / pp.unit_price_usd), 3) as avg_ratio,
    round(min((i.unit_price * 1.0) / pp.unit_price_usd), 3) as min_ratio,
    round(max((i.unit_price * 1.0) / pp.unit_price_usd), 3) as max_ratio
from {{ source("bronze_app", "order_items") }} i
inner join
    (
        select order_id, store_id, placed_at
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    ) o
    on i.order_id = o.order_id
inner join {{ source("bronze_app", "stores") }} s on o.store_id = s.store_id
asof inner join
    {{ source("bronze_app", "product_prices") }} pp
    on i.product_id = pp.product_id
    and o.placed_at >= pp.valid_from
where s.currency in ('SAR', 'AED')
group by currency, qtr
order by currency, qtr
