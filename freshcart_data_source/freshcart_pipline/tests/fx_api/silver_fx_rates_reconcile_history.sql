-- Reconciliation: the daily rates endpoint and the history endpoint must give the same
-- rate for the same date and currency
select
    r.rate_date,
    r.quote_currency,
    r.exchange_rate as rates_endpoint_rate,
    h.exchange_rate as history_endpoint_rate
from (select * from {{ ref("silver_rates") }} where is_latest_observation) as r
inner join
    (select * from {{ ref("silver_history") }} where is_latest_observation) as h
    on r.rate_date = h.rate_date
    and r.base_currency = h.base_currency
    and r.quote_currency = h.quote_currency
where r.exchange_rate != h.exchange_rate
