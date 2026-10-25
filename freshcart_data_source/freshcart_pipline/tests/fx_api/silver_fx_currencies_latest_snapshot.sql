-- The latest currencies snapshot must be one response listing exactly EGP, SAR and AED
{{ config(severity="warn") }}

select 'unexpected currency' as problem, ifNull(currency_code, 'NULL') as value
from {{ ref("silver_currencies") }}
where is_latest_snapshot and ifNull(currency_code, '') not in ('EGP', 'SAR', 'AED')

union all

select 'missing currency' as problem, expected as value
from (select arrayJoin(['EGP', 'SAR', 'AED']) as expected)
where
    expected not in (
        select ifNull(currency_code, '')
        from {{ ref("silver_currencies") }}
        where is_latest_snapshot
    )

union all

select 'latest snapshot count' as problem, toString(snapshots) as value
from
    (
        select uniqExact(batch_id) as snapshots
        from {{ ref("silver_currencies") }}
        where is_latest_snapshot
    )
where snapshots != 1
