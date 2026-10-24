-- Every product must have exactly one current price
select product_id, countIf(is_current) as current_rows
from {{ ref("silver_product_prices") }}
group by product_id
having current_rows != 1
