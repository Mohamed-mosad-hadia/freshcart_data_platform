"""Purpose: Define the raw FX API health-check Bronze table.
Execution Flow: Connect to ClickHouse, create the database and table if absent,
    then add missing columns to an existing table.
File Path: freshcart_data_source/ingestion/fx_api/DDL/health_check.py
Dependencies and Inputs: connection_clickhouse; ClickHouse connection.
Outputs: bronze_fx_api.health_check table.
"""

import logging

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


def health_check_table():
    """Create the raw health-check table, preserving any existing rows."""
    try:
        client = connection_clickhouse()
        client.execute("CREATE DATABASE IF NOT EXISTS bronze_fx_api")
        client.execute("""
            CREATE TABLE IF NOT EXISTS bronze_fx_api.health_check
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
        # Add the raw columns in place so historical rows are not discarded.
        client.execute("""
            ALTER TABLE bronze_fx_api.health_check
            ADD COLUMN IF NOT EXISTS batch_id UUID
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.health_check
            ADD COLUMN IF NOT EXISTS raw_payload String
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.health_check
            ADD COLUMN IF NOT EXISTS fetched_at DateTime64(3, 'Africa/Cairo')
                DEFAULT now64(3)
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.health_check
            ADD COLUMN IF NOT EXISTS source String DEFAULT 'fx_api'
        """)
        logger.info("Bronze health-check table is ready.")
    except Exception:
        logger.exception("Failed to create bronze_fx_api.health_check table")
        raise


if __name__ == "__main__":
    health_check_table()
