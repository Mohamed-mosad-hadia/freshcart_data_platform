-- Sanity of the provider's answers ("read its answers carefully"):
-- SAR and AED are pegged to USD, EGP must stay in a plausible range and must not
-- jump more than 5% from one business day to the next.
-- Warn: a real devaluation is possible, so a human must look before failing the pipeline.
{{ config(severity="warn") }}

with
    rates as (
        select
            rate_date,
            quote_currency,
            toFloat64(exchange_rate) as rate,
            lagInFrame(toFloat64(exchange_rate)) over (
                partition by quote_currency
                order by rate_date
                rows between 1 preceding and current row
            ) as prev_rate,
            row_number() over (partition by quote_currency order by rate_date) as rn
        from {{ ref("silver_history") }}
        where is_latest_observation
    )

select
    rate_date,
    quote_currency,
    rate,
    prev_rate,
    multiIf(
        quote_currency = 'SAR' and rate != 3.75, 'SAR peg broken (expected 3.75)',
        quote_currency = 'AED' and rate != 3.6725, 'AED peg broken (expected 3.6725)',
        quote_currency = 'EGP' and (rate < 30 or rate > 100), 'EGP outside 30-100',
        'jump above 5% vs previous business day'
    ) as problem
from rates
where
    (quote_currency = 'SAR' and rate != 3.75)
    or (quote_currency = 'AED' and rate != 3.6725)
    or (quote_currency = 'EGP' and (rate < 30 or rate > 100))
    or (rn > 1 and abs(rate - prev_rate) / prev_rate > 0.05)
