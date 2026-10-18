"""Purpose: Define the raw FX API rates Bronze table.
Execution Flow: Connect to ClickHouse, create the database and table if absent,
    then add missing columns to an existing table.
File Path: freshcart_data_source/ingestion/fx_api/DDL/rates.py
Dependencies and Inputs: connection_clickhouse; ClickHouse connection.
Outputs: bronze_fx_api.rates table.
"""

import logging

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


def rates_table():
    """Create the raw rates table without removing existing rows."""
    try:
        client = connection_clickhouse()
        client.execute("CREATE DATABASE IF NOT EXISTS bronze_fx_api")
        client.execute("""
            CREATE TABLE IF NOT EXISTS bronze_fx_api.rates
            (
                batch_id UUID,
                requested_date Date,
                raw_payload String,
                fetched_at DateTime64(3, 'Africa/Cairo') DEFAULT now64(3),
                source String DEFAULT 'fx_api'
            )
            ENGINE = MergeTree()
            ORDER BY (requested_date, fetched_at, batch_id)
        """)

        # CREATE TABLE IF NOT EXISTS leaves an older table's schema untouched.
        # The previous schema already has requested_date, fetched_at, and source.
        client.execute("""
            ALTER TABLE bronze_fx_api.rates
            ADD COLUMN IF NOT EXISTS batch_id UUID
        """)
        client.execute("""
            ALTER TABLE bronze_fx_api.rates
            ADD COLUMN IF NOT EXISTS raw_payload String
        """)
        logger.info("Bronze rates table is ready.")
    except Exception:
        logger.exception("Failed to create bronze_fx_api.rates table")
        raise


if __name__ == "__main__":
    rates_table()
