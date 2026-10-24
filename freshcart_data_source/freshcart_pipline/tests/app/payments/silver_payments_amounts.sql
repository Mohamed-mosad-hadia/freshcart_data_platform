select payment_id, amount from {{ ref("silver_payments") }} where amount <= 0
