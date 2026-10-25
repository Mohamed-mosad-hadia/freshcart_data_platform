-- The loader creates one Bronze table per CSV layout (table suffix = first 12 chars of
-- schema_hash). silver_supplier_stock only reads the three known layouts, so a new
-- layout would be silently missing from silver. Warn when an unknown layout is ingested.
{{ config(severity="warn") }}

select
    schema_hash,
    count() as files,
    min(source_file) as first_file,
    max(source_file) as last_file
from {{ source("bronze_suppliers", "ingested_files") }}
where
    substring(schema_hash, 1, 12)
    not in ('ce167a53a5e0', '7e84d7c978e4', '39c8d28c0bd9')
group by schema_hash
