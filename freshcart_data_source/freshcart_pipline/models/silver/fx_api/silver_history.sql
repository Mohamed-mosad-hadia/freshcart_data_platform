{{ config(materialized='table', schema='silver_fx_api', tags=['fx_api', 'silver']) }}

with responses as (
    select
        batch_id,
        request_start_date,
        request_end_date,
        raw_payload,
        fetched_at,
        source,
        isValidJSON(raw_payload) as is_valid_json,
        JSONExtractString(raw_payload, 'base') as raw_base_currency
    from {{ source('bronze_fx_api', 'history') }}
),
days as (
    select
        batch_id,
        request_start_date,
        request_end_date,
        fetched_at,
        source,
        is_valid_json,
        raw_base_currency,
        raw_day
    from responses
    left array join JSONExtractArrayRaw(raw_payload, 'days') as raw_day
),
expanded as (
    select
        batch_id,
        request_start_date,
        request_end_date,
        fetched_at,
        source,
        is_valid_json,
        raw_base_currency,
        JSONExtractString(raw_day, 'rate_date') as raw_rate_date,
        tupleElement(quote_rate, 1) as raw_quote_currency,
        tupleElement(quote_rate, 2) as raw_exchange_rate
    from days
    left array join JSONExtractKeysAndValuesRaw(raw_day, 'rates') as quote_rate
),
typed as (
    select
        batch_id,
        request_start_date,
        request_end_date,
        toDateOrNull(raw_rate_date) as rate_date,
        nullIf(upperUTF8(trimBoth(raw_base_currency)), '') as base_currency,
        nullIf(upperUTF8(trimBoth(raw_quote_currency)), '') as quote_currency,
        toDecimal64OrNull(raw_exchange_rate, 8) as exchange_rate,
        fetched_at,
        source,
        is_valid_json,
        raw_base_currency,
        raw_rate_date,
        raw_quote_currency,
        raw_exchange_rate
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
    request_start_date,
    request_end_date,
    rate_date,
    base_currency,
    quote_currency,
    exchange_rate,
    fetched_at,
    source,
    is_valid_json,
    isNull(rate_date) as has_invalid_rate_date,
    ifNull(
        isNotNull(rate_date) and (
            rate_date < request_start_date or rate_date > request_end_date
        ), false
    ) as has_out_of_window_date,
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
    raw_base_currency,
    raw_rate_date,
    raw_quote_currency,
    raw_exchange_rate
from ranked
