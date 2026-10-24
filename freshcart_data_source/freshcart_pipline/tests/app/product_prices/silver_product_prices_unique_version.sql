-- One row per product and valid_from
select product_id, valid_from, count() as n
from {{ ref("silver_product_prices") }}
group by product_id, valid_from
having count() > 1
