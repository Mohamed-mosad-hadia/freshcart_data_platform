-- The row chosen as latest must have a usable rate (gold converts with it)
select 'silver_rates' as model, batch_id, rate_date, quote_currency, exchange_rate
from {{ ref("silver_rates") }}
where is_latest_observation and has_unusable_exchange_rate

union all

select 'silver_history' as model, batch_id, rate_date, quote_currency, exchange_rate
from {{ ref("silver_history") }}
where is_latest_observation and has_unusable_exchange_rate
