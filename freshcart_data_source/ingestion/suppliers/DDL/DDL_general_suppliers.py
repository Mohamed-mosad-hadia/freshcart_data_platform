"""Define Bronze ClickHouse tables for general supplier CSV files.

Validate CSV headers, create one data table per distinct header schema, and
reuse the completed-file ledger without changing existing tables or rows.
"""

import hashlib
import json
import logging

from ingestion.suppliers.DDL.DDL_fresh_suppliers import (
    BRONZE_DB,
    LEDGER_TABLE,
    ROW_METADATA,
    _verify_columns,
    ensure_ledger,
    quote_identifier,
    validate_header,
)

logger = logging.getLogger(__name__)

TABLE_PREFIX = "general_stock"
SOURCE = "suppliers_general"


def schema_identity(header):
    """Return a stable table name and full hash for an ordered CSV header."""
    validate_header(header)
    encoded = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    digest = hashlib.sha256(encoded).hexdigest()
    return f"{TABLE_PREFIX}_{digest[:12]}", digest


def ensure_data_table(client, header):
    """Create or verify the table matching this file's exact ordered header."""
    table, schema_hash = schema_identity(header)
    columns = [f"{quote_identifier(name)} String" for name in header]
    columns.extend(
        [
            "batch_id UUID",
            "source_file String",
            "file_sha256 String",
            "source_row_number UInt64",
            "ingested_at DateTime64(3, 'Africa/Cairo') DEFAULT now64(3)",
            f"source String DEFAULT '{SOURCE}'",
        ]
    )
    definition = ",\n            ".join(columns)
    client.execute(f"""
        CREATE TABLE IF NOT EXISTS {quote_identifier(BRONZE_DB)}.{quote_identifier(table)}
        (
            {definition}
        )
        ENGINE = MergeTree()
        ORDER BY (source_file, file_sha256, source_row_number)
    """)
    _verify_columns(client, table, [(name, "String") for name in header] + list(ROW_METADATA))
    logger.debug("Bronze table ready: %s.%s", BRONZE_DB, table)
    return table, schema_hash
