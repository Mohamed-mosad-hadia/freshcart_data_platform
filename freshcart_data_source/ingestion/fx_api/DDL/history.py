"""Purpose: Define the raw FX API rate-history Bronze table.
Execution Flow: Connect to ClickHouse, create the database and table if absent,
    then add missing columns to an existing table.
File Path: freshcart_data_source/ingestion/fx_api/DDL/history.py
Dependencies and Inputs: connection_clickhouse; ClickHouse connection.
Outputs: bronze_fx_api.history table.
"""

import logging

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


def history_table():
    """Create the raw history table without removing existing rows."""
    try:
        client = connection_clickhouse()
        client.execute("CREATE DATABASE IF NOT EXISTS bronze_fx_api")
        client.execute("""
            CREATE TABLE IF NOT EXISTS bronze_fx_api.history
            (
                batch_id UUID,
                request_start_date Date,
                request_end_date Date,
                raw_payload String,
                fetched_at DateTime64(3, 'Africa/Cairo') DEFAULT now64(3),
                source String DEFAULT 'fx_api'
            )
            ENGINE = MergeTree()
            ORDER BY (request_start_date, request_end_date, fetched_at, batch_id)
        """)

        # CREATE TABLE IF NOT EXISTS does not update an existing schema.
        # Keep historical parsed rows while making future rows raw-only.
        client.execute("""
            ALTER TABLE bronze_fx_api.history
            ADD COLUMN IF NOT EXISTS batch_id UUID
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.history
            ADD COLUMN IF NOT EXISTS request_start_date Date
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.history
            ADD COLUMN IF NOT EXISTS request_end_date Date
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.history
            ADD COLUMN IF NOT EXISTS raw_payload String
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.history
            ADD COLUMN IF NOT EXISTS fetched_at DateTime64(3, 'Africa/Cairo')
                DEFAULT now64(3)
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.history
            ADD COLUMN IF NOT EXISTS source String DEFAULT 'fx_api'
        """)
        logger.info("Bronze history table is ready.")
    except Exception:
        logger.exception("Failed to create bronze_fx_api.history table")
        raise


if __name__ == "__main__":
    history_table()