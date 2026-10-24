{{
    config(
        materialized="table",
        tags=["app", "silver", "product_prices"],
        schema="silver_app",
    )
}}

-- bronze_app.product_prices is already a full price history (one row per version),
-- so we only add the SCD2 columns: version number, valid_to and is_current.
-- valid_from / valid_to are UTC timestamps: join orders on the timestamp, not the date.
select
    product_id,
    unit_price_usd,
    row_number() over (partition by product_id order by valid_from) as price_version,
    valid_from,
    leadInFrame(toNullable(valid_from)) over (
        partition by product_id
        order by valid_from
        rows between current row and 1 following
    ) as valid_to,
    valid_to is null as is_current,
    created_at,
    updated_at
from
    (
        select *
        from {{ source("bronze_app", "product_prices") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id, valid_from
    )
