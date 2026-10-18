"""Define Bronze ClickHouse tables for general supplier CSV files.

Validate CSV headers, create one data table per distinct header schema, and
reuse the completed-file ledger without changing existing tables or rows.
"""

import hashlib
import json
import logging
import sys
from clickhouse_connect import Client

logger = logging.getLogger(__name__)

TABLE_PREFIX = "general_stock"
SOURCE = "suppliers_general"


def get_client():
    """Create a ClickHouse client using clickhouse_connect."""
    try:
        client = Client(
            host="localhost",
            port=8123,
            username="freshcart_user",
            password="freshcart_ch_pass",
            database="bronze_suppliers",
            connect_timeout=10,
            send_hangups=True,
        )
        return client
    except Exception as e:
        logging.error("ClickHouse client creation failed: %s", e)
        sys.exit(1)


def schema_identity(header):
    """Return a stable table name and full hash for an ordered CSV header."""
    encoded = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    digest = hashlib.sha256(encoded).hexdigest()
    return f"{TABLE_PREFIX}_{digest[:12]}", digest


def ensure_data_table(client, header):
    """Create or verify the table matching this file's exact ordered header."""
    table, schema_hash = schema_identity(header)
    columns = [f"`{name}` String" for name in header]
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
        CREATE TABLE IF NOT EXISTS {table}
        (
            {definition}
        )
        ENGINE = MergeTree()
        ORDER BY (source_file, file_sha256, source_row_number)
    """)
    logger.debug("Bronze table ready: %s.%s", "bronze_suppliers", table)
    return table, schema_hash