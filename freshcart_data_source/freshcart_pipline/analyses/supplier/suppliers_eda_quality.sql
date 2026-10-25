-- HOW TO RUN: this file holds many separate queries. Select ONE block (from its
-- comment to the blank line) and preview the selection. Previewing the whole file
-- sends all queries as one statement and fails with "Syntax error ... (SYNTAX_ERROR)".

-- ===================== FRESH supplier (fresh_stock) =====================
-- overview: rows, files, days
select
    count() as total_rows,
    uniqExact(source_file) as files,
    min(stock_date) as min_stock_date,
    max(stock_date) as max_stock_date
from {{ source("bronze_suppliers", "fresh_stock") }}

-- rows per file (360 = 60 products x 6 stores, 420 = 7 stores)
select rows_in_file, count() as files, min(source_file), max(source_file)
from
    (
        select source_file, count() as rows_in_file
        from {{ source("bronze_suppliers", "fresh_stock") }}
        group by source_file
    )
group by rows_in_file
order by rows_in_file

-- duplicates: same product / store / stock_date (inside or across files)
select product_id, store_id, stock_date, count() as copies, groupArray(source_file) as files
from {{ source("bronze_suppliers", "fresh_stock") }}
group by product_id, store_id, stock_date
having copies > 1
limit 20

-- supplier column values
select supplier, count() as rows_n
from {{ source("bronze_suppliers", "fresh_stock") }}
group by supplier

-- product_id / store_id: numeric? blank?
select
    countIf(trim(product_id) = '') as blank_product,
    countIf(toInt32OrNull(trim(product_id)) is null) as non_numeric_product,
    countIf(trim(store_id) = '') as blank_store,
    countIf(toInt32OrNull(trim(store_id)) is null) as non_numeric_store,
    groupUniqArray(store_id) as store_values,
    uniqExact(product_id) as products
from {{ source("bronze_suppliers", "fresh_stock") }}

-- stock_date: format and match with the file name date
select
    countIf(toDateOrNull(stock_date) is null) as unparseable_date,
    countIf(
        toString(toDateOrNull(stock_date))
        != extract(source_file, '(\\d{4}-\\d{2}-\\d{2})')
    ) as date_differs_from_file,
    groupArrayIf(5)(stock_date, toDateOrNull(stock_date) is null) as bad_examples
from {{ source("bronze_suppliers", "fresh_stock") }}

-- quantity_on_hand / reorder_level
select
    countIf(trim(quantity_on_hand) = '') as blank_qty,
    countIf(toInt64OrNull(trim(quantity_on_hand)) is null) as non_numeric_qty,
    countIf(toInt64OrNull(trim(quantity_on_hand)) < 0) as negative_qty,
    countIf(toInt64OrNull(trim(quantity_on_hand)) = 0) as zero_qty,
    min(toInt64OrNull(trim(quantity_on_hand))) as min_qty,
    max(toInt64OrNull(trim(quantity_on_hand))) as max_qty,
    countIf(toInt64OrNull(trim(reorder_level)) is null) as non_numeric_reorder,
    countIf(toInt64OrNull(trim(reorder_level)) <= 0) as non_positive_reorder,
    countIf(
        toInt64OrNull(trim(quantity_on_hand)) < toInt64OrNull(trim(reorder_level))
    ) as below_reorder,
    groupArrayIf(5)(
        quantity_on_hand, toInt64OrNull(trim(quantity_on_hand)) is null
    ) as bad_qty_examples
from {{ source("bronze_suppliers", "fresh_stock") }}

-- products: all in the catalogue? which categories?
select
    p.category,
    uniqExact(f.product_id) as products,
    countIf(p.product_id = 0) as rows_unknown_product
from {{ source("bronze_suppliers", "fresh_stock") }} as f
left join
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) as p
    on toInt32OrZero(trim(f.product_id)) = p.product_id
group by p.category
order by p.category

-- ===================== GENERAL supplier, old layout (Qty) =====================
-- overview
select
    count() as total_rows,
    uniqExact(source_file) as files,
    min(source_file),
    max(source_file)
from {{ source("bronze_suppliers", "general_stock_qty") }}

-- duplicates: same product / store / date
select Product, Store, Date, count() as copies, groupArray(source_file) as files
from {{ source("bronze_suppliers", "general_stock_qty") }}
group by Product, Store, Date
having copies > 1
limit 20

-- columns: supplier, ids, date format, quantities
select
    groupUniqArray(Supplier) as supplier_values,
    countIf(toInt32OrNull(trim(Product)) is null) as non_numeric_product,
    groupUniqArray(Store) as store_values,
    countIf(parseDateTimeOrNull(Date, '%d/%m/%Y') is null) as unparseable_date,
    countIf(
        formatDateTime(parseDateTimeOrNull(Date, '%d/%m/%Y'), '%Y%m%d')
        != extract(source_file, '(\\d{8})')
    ) as date_differs_from_file,
    groupArrayIf(5)(Date, parseDateTimeOrNull(Date, '%d/%m/%Y') is null) as bad_dates,
    countIf(toInt64OrNull(trim(Qty)) is null) as non_numeric_qty,
    countIf(toInt64OrNull(trim(Qty)) < 0) as negative_qty,
    countIf(toInt64OrNull(trim(Qty)) = 0) as zero_qty,
    countIf(toInt64OrNull(trim(MinQty)) is null) as non_numeric_minqty,
    countIf(toInt64OrNull(trim(Qty)) < toInt64OrNull(trim(MinQty))) as below_min,
    groupArrayIf(5)(Qty, toInt64OrNull(trim(Qty)) is null) as bad_qty_examples
from {{ source("bronze_suppliers", "general_stock_qty") }}

-- ===================== GENERAL supplier, new layout (QtyOnHand + UnitCost) =====================
-- overview: when did the layout change?
select
    count() as total_rows,
    uniqExact(source_file) as files,
    min(source_file),
    max(source_file)
from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}

-- rows per file and stores per file
select source_file, count() as rows_n, uniqExact(Store) as stores, groupUniqArray(Store) as store_values
from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
group by source_file
order by source_file

-- duplicates: same product / store / date
select Product, Store, Date, count() as copies, groupArray(source_file) as files
from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
group by Product, Store, Date
having copies > 1
limit 20

-- columns: supplier, ids, date format, quantities, unit cost (decimal comma)
select
    groupUniqArray(Supplier) as supplier_values,
    countIf(toInt32OrNull(trim(Product)) is null) as non_numeric_product,
    countIf(parseDateTimeOrNull(Date, '%d/%m/%Y') is null) as unparseable_date,
    countIf(
        formatDateTime(parseDateTimeOrNull(Date, '%d/%m/%Y'), '%Y%m%d')
        != extract(source_file, '(\\d{8})')
    ) as date_differs_from_file,
    countIf(toInt64OrNull(trim(QtyOnHand)) is null) as non_numeric_qty,
    countIf(toInt64OrNull(trim(QtyOnHand)) < 0) as negative_qty,
    countIf(toInt64OrNull(trim(QtyOnHand)) = 0) as zero_qty,
    countIf(toInt64OrNull(trim(MinQty)) is null) as non_numeric_minqty,
    countIf(toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2) is null) as bad_unit_cost,
    countIf(toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2) <= 0) as non_positive_cost,
    min(toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2)) as min_cost,
    max(toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2)) as max_cost,
    countIf(position(UnitCost, ',') = 0) as cost_without_comma,
    groupArrayIf(5)(UnitCost, toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2) is null) as bad_cost_examples
from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}

-- unit cost vs catalogue price (cost should be below the selling price)
select
    countIf(c.unit_cost >= p.unit_price_usd) as cost_not_below_price,
    round(avg(c.unit_cost / p.unit_price_usd), 3) as avg_cost_to_price_ratio
from
    (
        select
            toInt32OrZero(trim(Product)) as product_id,
            any(toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2)) as unit_cost
        from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
        group by product_id
    ) as c
inner join
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) as p
    using product_id

-- GENERAL products: all in the catalogue? which categories? (both layouts)
select
    p.category,
    uniqExact(g.product) as products,
    countIf(p.product_id = 0) as rows_unknown_product
from
    (
        select Product as product from {{ source("bronze_suppliers", "general_stock_qty") }}
        union all
        select Product from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
    ) as g
left join
    (
        select *
        from {{ source("bronze_app", "products") }}
        order by updated_at desc, created_at desc
        limit 1 by product_id
    ) as p
    on toInt32OrZero(trim(g.product)) = p.product_id
group by p.category
order by p.category

-- ===================== across suppliers =====================
-- products delivered by both suppliers? products never covered?
select
    uniqExact(product_id) as catalogue_products,
    countIf(in_fresh and in_general) as in_both,
    countIf(not in_fresh and not in_general) as in_neither
from
    (
        select
            product_id,
            product_id in (
                select toInt32OrZero(trim(product_id))
                from {{ source("bronze_suppliers", "fresh_stock") }}
            ) as in_fresh,
            product_id in (
                select toInt32OrZero(trim(Product))
                from {{ source("bronze_suppliers", "general_stock_qty") }}
                union all
                select toInt32OrZero(trim(Product))
                from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
            ) as in_general
        from {{ source("bronze_app", "products") }}
    )

-- stores in supplier files vs stores table (store 7 appears from 2026-10-19)
select
    s.store_id as file_store,
    st.store_name,
    st.opened_at,
    min(s.file_day) as first_file_day,
    max(s.file_day) as last_file_day
from
    (
        select toInt32OrZero(trim(store_id)) as store_id, toDateOrNull(stock_date) as file_day
        from {{ source("bronze_suppliers", "fresh_stock") }}
        union all
        select toInt32OrZero(trim(Store)), toDate(parseDateTimeOrNull(Date, '%d/%m/%Y'))
        from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
    ) as s
left join {{ source("bronze_app", "stores") }} as st on s.store_id = st.store_id
group by s.store_id, st.store_name, st.opened_at
order by s.store_id

-- missing days: every day must have one FRESH and one GENERAL file
select file_day, countIf(supplier = 'FRESH') as fresh_files, countIf(supplier = 'GENERAL') as general_files
from
    (
        select distinct 'FRESH' as supplier, toDateOrNull(stock_date) as file_day
        from {{ source("bronze_suppliers", "fresh_stock") }}
        union all
        select distinct 'GENERAL', toDate(parseDateTimeOrNull(Date, '%d/%m/%Y'))
        from {{ source("bronze_suppliers", "general_stock_qty") }}
        union all
        select distinct 'GENERAL', toDate(parseDateTimeOrNull(Date, '%d/%m/%Y'))
        from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
    )
group by file_day
having fresh_files != 1 or general_files != 1
order by file_day

-- late GENERAL files: ingested on a later day than the stock date
select
    toDate(ingested_at) - toDate(parseDateTimeOrNull(Date, '%d/%m/%Y')) as days_late,
    uniqExact(source_file) as files
from
    (
        select Date, source_file, ingested_at from {{ source("bronze_suppliers", "general_stock_qty") }}
        union all
        select Date, source_file, ingested_at from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
    )
group by days_late
order by days_late
