-- Base must be USD and quotes only EGP / SAR / AED (rates and history)
select 'silver_rates' as model, batch_id, rate_date, base_currency, quote_currency
from {{ ref("silver_rates") }}
where
    base_currency is null
    or quote_currency is null
    or base_currency != 'USD'
    or quote_currency not in ('EGP', 'SAR', 'AED')

union all

select 'silver_history' as model, batch_id, rate_date, base_currency, quote_currency
from {{ ref("silver_history") }}
where
    base_currency is null
    or quote_currency is null
    or base_currency != 'USD'
    or quote_currency not in ('EGP', 'SAR', 'AED')
