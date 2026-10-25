{{ config(materialized='table', schema='silver_fx_api', tags=['fx_api', 'silver']) }}

with responses as (
    select
        batch_id,
        raw_payload,
        fetched_at,
        source,
        isValidJSON(raw_payload) as is_valid_json,
        JSONExtractString(raw_payload, 'base') as raw_base_currency,
        row_number() over (order by fetched_at desc, batch_id desc) as response_rank
    from {{ source('bronze_fx_api', 'currencies') }}
),
expanded as (
    select
        batch_id,
        fetched_at,
        source,
        is_valid_json,
        response_rank,
        raw_base_currency,
        raw_currency_code,
        JSONExtractRaw(raw_payload, 'pegged', raw_currency_code) as raw_pegged_rate,
        has(JSONExtract(raw_payload, 'floating', 'Array(String)'), raw_currency_code)
            as is_floating
    from responses
    left array join JSONExtract(raw_payload, 'currencies', 'Array(String)')
        as raw_currency_code
)
select
    batch_id,
    nullIf(upperUTF8(trimBoth(raw_base_currency)), '') as base_currency,
    nullIf(upperUTF8(trimBoth(raw_currency_code)), '') as currency_code,
    toDecimal64OrNull(raw_pegged_rate, 8) as pegged_rate,
    is_floating,
    fetched_at,
    source,
    is_valid_json,
    response_rank = 1 as is_latest_snapshot,
    not match(upperUTF8(trimBoth(raw_base_currency)), '^[A-Z]{3}$')
        as has_invalid_base_currency,
    not match(upperUTF8(trimBoth(raw_currency_code)), '^[A-Z]{3}$')
        as has_invalid_currency_code,
    raw_base_currency,
    raw_currency_code,
    raw_pegged_rate
from expanded
