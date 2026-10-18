"""Purpose: Define the raw FX API currencies Bronze table.
Execution Flow: Connect to ClickHouse, create the database and table if absent,
    then add missing columns to an existing table.
File Path: freshcart_data_source/ingestion/fx_api/DDL/currencies.py
Dependencies and Inputs: connection_clickhouse; ClickHouse connection.
Outputs: bronze_fx_api.currencies table.
"""

import logging

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


def currencies_table():
    """Create the raw currencies table without removing existing rows."""
    try:
        client = connection_clickhouse()
        client.execute("CREATE DATABASE IF NOT EXISTS bronze_fx_api")
        client.execute("""
            CREATE TABLE IF NOT EXISTS bronze_fx_api.currencies
            (
                batch_id UUID,
                raw_payload String,
                fetched_at DateTime64(3, 'Africa/Cairo') DEFAULT now64(3),
                source String DEFAULT 'fx_api'
            )
            ENGINE = MergeTree()
            ORDER BY (fetched_at, batch_id)
        """)

        # CREATE TABLE IF NOT EXISTS leaves an older table's schema untouched.
        # Add only the columns missing from the previous currencies schema.
        client.execute("""
            ALTER TABLE bronze_fx_api.currencies
            ADD COLUMN IF NOT EXISTS batch_id UUID
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.currencies
            ADD COLUMN IF NOT EXISTS raw_payload String
        """)
        logger.info("Bronze currencies table is ready.")
    except Exception:
        logger.exception("Failed to create bronze_fx_api.currencies table")
        raise


if __name__ == "__main__":
    currencies_table()