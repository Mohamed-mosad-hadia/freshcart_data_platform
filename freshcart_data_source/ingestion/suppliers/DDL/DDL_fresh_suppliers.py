"""Define Bronze ClickHouse tables for fresh supplier CSV files.

Validate CSV headers, create one data table per distinct header schema, and
create a file-ingestion ledger. Existing tables and rows are left in place.
"""

import hashlib
import json
import logging

logger = logging.getLogger(__name__)

BRONZE_DB = "bronze_suppliers"
TABLE_PREFIX = "fresh_stock"
LEDGER_TABLE = "ingested_files"
SOURCE = "suppliers_fresh"

ROW_METADATA = (
    ("batch_id", "UUID"),
    ("source_file", "String"),
    ("file_sha256", "String"),
    ("source_row_number", "UInt64"),
    ("ingested_at", "DateTime64(3, 'Africa/Cairo')"),
    ("source", "String"),
)
LEDGER_COLUMNS = (
    ("source_file", "String"),
    ("file_sha256", "String"),
    ("schema_hash", "String"),
    ("row_count", "UInt64"),
    ("batch_id", "UUID"),
    ("ingested_at", "DateTime64(3, 'Africa/Cairo')"),
)


def quote_identifier(name):
    """Quote a CSV header or fixed table name for ClickHouse SQL."""
    if not name or any(char in name for char in "\x00\r\n"):
        raise ValueError(f"Invalid ClickHouse identifier: {name!r}")
    return "`" + name.replace("\\", "\\\\").replace("`", "\\`") + "`"


def validate_header(header):
    if not header:
        raise ValueError("CSV has no header")
    if len(set(header)) != len(header):
        raise ValueError("CSV header contains duplicate column names")
    reserved = {name for name, _ in ROW_METADATA}
    for name in header:
        quote_identifier(name)
        if name in reserved:
            raise ValueError(f"CSV column conflicts with ingestion metadata: {name!r}")


def schema_identity(header):
    """Return a stable table name and full hash for an ordered CSV header."""
    validate_header(header)
    encoded = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    digest = hashlib.sha256(encoded).hexdigest()
    return f"{TABLE_PREFIX}_{digest[:12]}", digest


def _verify_columns(client, table, expected):
    actual = client.execute(
        """SELECT name, type FROM system.columns
           WHERE database = %(database)s AND table = %(table)s
           ORDER BY position""",
        {"database": BRONZE_DB, "table": table},
    )
    if actual != list(expected):
        raise ValueError(
            f"Existing {BRONZE_DB}.{table} schema differs from expected: {actual!r}"
        )


def ensure_ledger(client):
    """Create the Bronze database and completed-file ledger if absent."""
    client.execute(f"CREATE DATABASE IF NOT EXISTS {quote_identifier(BRONZE_DB)}")
    client.execute(f"""
        CREATE TABLE IF NOT EXISTS {quote_identifier(BRONZE_DB)}.{quote_identifier(LEDGER_TABLE)}
        (
            source_file String,
            file_sha256 String,
            schema_hash String,
            row_count UInt64,
            batch_id UUID,
            ingested_at DateTime64(3, 'Africa/Cairo') DEFAULT now64(3)
        )
        ENGINE = MergeTree()
        ORDER BY (source_file, file_sha256)
    """)
    _verify_columns(client, LEDGER_TABLE, LEDGER_COLUMNS)


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
