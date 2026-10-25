{{ config(materialized='table', schema='silver_fx_api', tags=['fx_api', 'silver']) }}

with responses as (
    select
        batch_id,
        requested_date,
        raw_payload,
        fetched_at,
        source,
        isValidJSON(raw_payload) as is_valid_json,
        JSONExtractString(raw_payload, 'base') as raw_base_currency,
        JSONExtractString(raw_payload, 'rate_date') as raw_rate_date,
        JSONExtractString(raw_payload, 'published_at') as raw_published_at
    from {{ source('bronze_fx_api', 'rates') }}
),
expanded as (
    select
        batch_id,
        requested_date,
        fetched_at,
        source,
        is_valid_json,
        raw_base_currency,
        raw_rate_date,
        raw_published_at,
        tupleElement(quote_rate, 1) as raw_quote_currency,
        tupleElement(quote_rate, 2) as raw_exchange_rate
    from responses
    left array join JSONExtractKeysAndValuesRaw(raw_payload, 'rates') as quote_rate
),
typed as (
    select
        batch_id,
        requested_date,
        toDateOrNull(raw_rate_date) as rate_date,
        nullIf(upperUTF8(trimBoth(raw_base_currency)), '') as base_currency,
        nullIf(upperUTF8(trimBoth(raw_quote_currency)), '') as quote_currency,
        toDecimal64OrNull(raw_exchange_rate, 8) as exchange_rate,
        toTimeZone(
            parseDateTime64BestEffortOrNull(raw_published_at, 3), 'UTC'
        ) as published_at,
        fetched_at,
        source,
        is_valid_json,
        raw_exchange_rate,
        raw_base_currency,
        raw_quote_currency,
        raw_rate_date
    from expanded
),
ranked as (
    select
        *,
        count() over (
            partition by rate_date, base_currency, quote_currency
        ) as observation_version_count,
        row_number() over (
            partition by rate_date, base_currency, quote_currency
            order by fetched_at desc, batch_id desc
        ) as observation_version_rank
    from typed
)
select
    batch_id,
    requested_date,
    rate_date,
    base_currency,
    quote_currency,
    exchange_rate,
    published_at,
    fetched_at,
    source,
    is_valid_json,
    isNull(rate_date) as has_invalid_rate_date,
    isNull(base_currency) or not match(ifNull(base_currency, ''), '^[A-Z]{3}$')
        as has_invalid_base_currency,
    isNull(quote_currency) or not match(ifNull(quote_currency, ''), '^[A-Z]{3}$')
        as has_invalid_quote_currency,
    ifNull(isNull(exchange_rate) or exchange_rate <= 0, true)
        as has_unusable_exchange_rate,
    observation_version_count,
    observation_version_count > 1 as has_duplicate_observation,
    observation_version_rank = 1 and isNotNull(rate_date)
        and isNotNull(base_currency) and isNotNull(quote_currency)
        as is_latest_observation,
    raw_exchange_rate,
    raw_base_currency,
    raw_quote_currency,
    raw_rate_date
from ranked
