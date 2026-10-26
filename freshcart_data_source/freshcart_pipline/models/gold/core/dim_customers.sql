{{ config(materialized="table", tags=["gold", "core"], schema="gold_core") }}

-- One row per person: silver_customers already keeps one account per email
-- (duplicate accounts merged) and removes test accounts; silver_orders remaps the
-- orders of duplicate accounts to the kept customer_id.
select
    customer_id,
    first_name,
    last_name,
    email,
    phone,
    city,
    signup_date
from {{ ref("silver_customers") }}
