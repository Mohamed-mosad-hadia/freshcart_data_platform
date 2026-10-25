{{ config(materialized='table', schema='silver_fx_api', tags=['fx_api', 'silver']) }}

with parsed as (
    select
        batch_id,
        nullIf(lowerUTF8(trimBoth(JSONExtractString(raw_payload, 'status'))), '')
            as health_status,
        toTimeZone(
            parseDateTime64BestEffortOrNull(
                JSONExtractString(raw_payload, 'time'), 3
            ), 'UTC'
        ) as api_checked_at,
        fetched_at,
        source,
        isValidJSON(raw_payload) as is_valid_json,
        JSONExtractString(raw_payload, 'status') as raw_health_status,
        JSONExtractString(raw_payload, 'time') as raw_api_time
    from {{ source('bronze_fx_api', 'health_check') }}
)
select
    batch_id,
    health_status,
    api_checked_at,
    fetched_at,
    source,
    is_valid_json,
    ifNull(health_status = 'ok', false) as is_healthy_response,
    isNull(health_status) as has_missing_status,
    isNull(api_checked_at) as has_invalid_api_time,
    raw_health_status,
    raw_api_time
from parsed
