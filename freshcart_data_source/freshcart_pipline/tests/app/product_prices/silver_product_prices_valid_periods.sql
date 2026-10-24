-- Periods must move forward: valid_to after valid_from, and only the current row is open
select product_id, price_version, valid_from, valid_to, is_current
from {{ ref("silver_product_prices") }}
where
    (valid_to is not null and valid_to <= valid_from)
    or (valid_to is null and not is_current)
