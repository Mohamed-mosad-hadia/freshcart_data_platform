-- is_latest_observation must select exactly one row per rate_date / base / quote
select 'silver_rates' as model, rate_date, base_currency, quote_currency, count() as latest_rows
from {{ ref("silver_rates") }}
where is_latest_observation
group by rate_date, base_currency, quote_currency
having latest_rows > 1

union all

select 'silver_history' as model, rate_date, base_currency, quote_currency, count() as latest_rows
from {{ ref("silver_history") }}
where is_latest_observation
group by rate_date, base_currency, quote_currency
having latest_rows > 1
