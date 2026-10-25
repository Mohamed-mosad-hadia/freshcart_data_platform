{{
    config(
        materialized="table",
        tags=["suppliers", "silver", "stock"],
        schema="silver_suppliers",
    )
}}

-- One row per supplier / product / store / stock_date (end-of-day stock at 22:00).
-- Bronze has one table per CSV layout; each layout is mapped to the same columns here.
-- If the loader creates a new layout table, add it below (test silver_supplier_stock_new_layout warns).
with
    fresh as (
        select
            upper(trim(supplier)) as supplier,
            toInt32OrNull(trim(product_id)) as product_id,
            toInt32OrNull(trim(store_id)) as store_id,
            toDateOrNull(trim(stock_date)) as stock_date,
            toInt64OrNull(trim(quantity_on_hand)) as quantity_on_hand,
            toInt64OrNull(trim(reorder_level)) as reorder_level,
            cast(null as Nullable(Decimal(18, 2))) as unit_cost,
            'fresh_v1' as source_layout,
            source_file,
            ingested_at
        from {{ source("bronze_suppliers", "fresh_stock") }}
    ),

    -- GENERAL until 2026-10-16: Qty / MinQty, dates dd/mm/yyyy, 'N/A' when not counted
    general_qty as (
        select
            upper(trim(Supplier)) as supplier,
            toInt32OrNull(trim(Product)) as product_id,
            toInt32OrNull(trim(Store)) as store_id,
            toDate(parseDateTimeOrNull(trim(Date), '%d/%m/%Y')) as stock_date,
            toInt64OrNull(trim(Qty)) as quantity_on_hand,
            toInt64OrNull(trim(MinQty)) as reorder_level,
            cast(null as Nullable(Decimal(18, 2))) as unit_cost,
            'general_v1_qty' as source_layout,
            source_file,
            ingested_at
        from {{ source("bronze_suppliers", "general_stock_qty") }}
    ),

    -- GENERAL from 2026-10-17: QtyOnHand / MinQty / UnitCost (decimal comma: 11,33)
    general_qtyonhand as (
        select
            upper(trim(Supplier)) as supplier,
            toInt32OrNull(trim(Product)) as product_id,
            toInt32OrNull(trim(Store)) as store_id,
            toDate(parseDateTimeOrNull(trim(Date), '%d/%m/%Y')) as stock_date,
            toInt64OrNull(trim(QtyOnHand)) as quantity_on_hand,
            toInt64OrNull(trim(MinQty)) as reorder_level,
            toDecimal64OrNull(replaceAll(trim(UnitCost), ',', '.'), 2) as unit_cost,
            'general_v2_qtyonhand' as source_layout,
            source_file,
            ingested_at
        from {{ source("bronze_suppliers", "general_stock_qtyonhand") }}
    ),

    unioned as (
        select * from fresh
        union all
        select * from general_qty
        union all
        select * from general_qtyonhand
    ),

    -- safety: keep the latest ingested row if a day is ever delivered twice
    deduped as (
        select *
        from unioned
        order by ingested_at desc
        limit 1 by supplier, product_id, store_id, stock_date
    )

select
    s.supplier,
    s.product_id,
    s.store_id,
    s.stock_date,
    s.quantity_on_hand,
    s.reorder_level,
    s.unit_cost,
    s.quantity_on_hand is null as is_qty_missing,
    ifNull(s.quantity_on_hand = 0, false) as is_stockout,
    ifNull(s.quantity_on_hand < s.reorder_level, false) as is_below_reorder,
    st.store_id != 0 and s.stock_date < toDate(st.opened_at) as is_before_store_opening,
    s.source_layout,
    s.source_file,
    s.ingested_at
from deduped as s
left join {{ ref("silver_stores") }} as st on s.store_id = st.store_id
