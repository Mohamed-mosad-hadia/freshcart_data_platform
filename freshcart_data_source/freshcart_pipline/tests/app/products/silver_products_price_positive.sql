select product_id, product_name, unit_price_usd
from {{ ref("silver_products") }}
where unit_price_usd <= 0
