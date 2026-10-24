select
    concat('[', payment_status, ']') as status,
    concat('[', payment_method, ']') as method,
    count() as payments,
    sum(amount < 0) as negative_amount,
    sum(amount = 0) as zero_amount,
    min(amount) as min_amount,
    max(amount) as max_amount,
    sum(paid_at < '2000-01-01') as paid_at_default,
    sum(paid_at > now()) as paid_at_future,
    sum(updated_at < created_at) as updated_before_created
from {{ source("bronze_app", "payments") }}
group by payment_status, payment_method
order by payments desc

select
    count() as orders_with_both,
    sum(abs(refunded - paid) < 0.01) as full_refund,
    sum(refunded < paid - 0.01) as partial_refund,
    sum(refunded > paid + 0.01) as refund_exceeds_paid
from
    (
        select
            order_id,
            sumif(amount, payment_status = 'paid') as paid,
            sumif(amount, payment_status = 'refunded') as refunded
        from {{ source("bronze_app", "payments") }}
        group by order_id
        having
            countif(payment_status = 'paid') > 0
            and countif(payment_status = 'refunded') > 0
    )

select
    p.method as method,
    count() as orders,
    round(avg(p.refunded / p.paid), 3) as avg_refund_share,
    round(min(p.refunded / p.paid), 3) as min_share,
    round(max(p.refunded / p.paid), 3) as max_share
from
    (
        select
            order_id,
            any(payment_method) as method,
            sum(if(payment_status = 'paid', amount, 0)) as paid,
            sum(if(payment_status = 'refunded', amount, 0)) as refunded
        from {{ source("bronze_app", "payments") }}
        group by order_id
        having sum(payment_status = 'paid') > 0 and sum(payment_status = 'refunded') > 0
    ) p
group by method
order by orders desc

select
    o.order_status as order_status,
    count(distinct p.order_id) as orders_with_refund,
    count() as refund_rows
from {{ source("bronze_app", "payments") }} p
inner join
    (
        select order_id, order_status
        from {{ source("bronze_app", "orders") }}
        order by updated_at desc, created_at desc
        limit 1 by order_id
    ) o
    on p.order_id = o.order_id
where p.payment_status = 'refunded'
group by order_status

select
    order_id,
    count() as refunds,
    grouparray(amount) as amounts,
    grouparray(payment_method) as methods
from {{ source("bronze_app", "payments") }}
where
    payment_status = 'refunded'
    and order_id in (
        select order_id
        from {{ source("bronze_app", "payments") }}
        where payment_status = 'refunded'
        group by order_id
        having count() > 1
    )
group by order_id
limit 20

select
    count() as orders,
    sum(amount_1 = amount_2) as same_amount_twice,
    sum(amount_1 != amount_2) as different_amounts
from
    (
        select order_id, min(amount) as amount_1, max(amount) as amount_2
        from {{ source("bronze_app", "payments") }}
        where payment_status = 'paid'
        group by order_id
        having count() > 1
    )

select
    payment_status,
    count() as duplicated_orders,
    min(order_id) as min_order_id,
    max(order_id) as max_order_id,
    min(id_gap) as min_payment_id_gap,
    max(id_gap) as max_payment_id_gap,
    min(seconds_apart) as min_seconds_apart,
    max(seconds_apart) as max_seconds_apart
from
    (
        select
            order_id,
            payment_status,
            max(payment_id) - min(payment_id) as id_gap,
            date_diff('second', min(created_at), max(created_at)) as seconds_apart
        from {{ source("bronze_app", "payments") }}
        group by order_id, payment_status, payment_method, amount
        having count() > 1
    )
group by payment_status
