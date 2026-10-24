select store_id, country, currency
from {{ ref("silver_stores") }}
where
    (country = 'EG' and currency != 'EGP')
    or (country = 'SA' and currency != 'SAR')
    or (country = 'AE' and currency != 'AED')
