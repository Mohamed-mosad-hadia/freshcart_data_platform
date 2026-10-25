-- FRESH supplies fruits & vegetables, dairy, bakery, meat & fish; GENERAL everything else
select s.supplier, s.product_id, p.category, count() as rows_n
from {{ ref("silver_supplier_stock") }} as s
inner join {{ ref("silver_products") }} as p on s.product_id = p.product_id
where
    (s.supplier = 'FRESH') != (
        p.category in ('Fruits & Vegetables', 'Dairy', 'Bakery', 'Meat & Fish')
    )
group by s.supplier, s.product_id, p.category
