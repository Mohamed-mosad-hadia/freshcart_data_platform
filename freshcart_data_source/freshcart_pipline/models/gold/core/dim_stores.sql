{{ config(materialized="table", tags=["gold", "core"], schema="gold_core") }}

select
    store_id,
    store_name,
    city,
    country,
    currency,
    toDate(opened_at) as opened_on
from {{ ref("silver_stores") }}
