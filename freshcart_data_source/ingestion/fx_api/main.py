"""Purpose: Single entry point for the FX API Bronze pipeline.
Execution Flow: create_tables() builds every Bronze table, then each load_*()
    function ingests one endpoint. run_all() chains both stages. Airflow calls
    the stage functions as separate tasks; the CLI below runs them locally.
File Path: freshcart_data_source/ingestion/fx_api/main.py
Dependencies and Inputs: ingestion.fx_api.DDL.*, ingestion.fx_api.Load.*;
    FX_API_KEY env var (history loader); ClickHouse and the FX API running.
Outputs: Tables and rows in bronze_fx_api.
Usage (run from freshcart_data_source/):
    python -m ingestion.fx_api.main --stage all
    python -m ingestion.fx_api.main --stage load --requested-date 2023-01-05
    

## Running Commands:
python -m ingestion.fx_api.main --stage ddl     # الجداول فقط
python -m ingestion.fx_api.main --stage load    # التحميل فقط
python -m ingestion.fx_api.main --stage all     # الاتنين

"""

import argparse
import logging

from ingestion.fx_api.DDL.currencies import currencies_table
from ingestion.fx_api.DDL.health_check import health_check_table
from ingestion.fx_api.DDL.history import history_table
from ingestion.fx_api.DDL.rates import rates_table
from ingestion.fx_api.Load.currencies import insert_bronze_currencies
from ingestion.fx_api.Load.health_check import insert_bronze_health_check
from ingestion.fx_api.Load.history import insert_bronze_history
from ingestion.fx_api.Load.rates import insert_bronze_rates

logger = logging.getLogger(__name__)


def create_tables():
    """Create all Bronze tables (idempotent)."""
    for create in (currencies_table, health_check_table, rates_table, history_table):
        create()
    logger.info("All FX API Bronze tables are ready.")


def load_health_check():
    insert_bronze_health_check()


def load_currencies():
    insert_bronze_currencies()


def load_rates(requested_date="2023-01-01"):
    insert_bronze_rates(requested_date)


def load_history(start_date=None, end_date=None):
    insert_bronze_history(start_date, end_date)


def load_all(requested_date="2023-01-01", start_date=None, end_date=None):
    """Run every loader; health check goes first as a cheap API probe."""
    load_health_check()
    load_currencies()
    load_rates(requested_date)
    load_history(start_date, end_date)


def run_all(requested_date="2023-01-01", start_date=None, end_date=None):
    create_tables()
    load_all(requested_date, start_date, end_date)


def main():
    parser = argparse.ArgumentParser(description="FX API Bronze pipeline")
    parser.add_argument("--stage", choices=("ddl", "load", "all"), default="all")
    parser.add_argument("--requested-date", default="2023-01-01")
    parser.add_argument("--start-date")
    parser.add_argument("--end-date")
    args = parser.parse_args()

    if args.stage == "ddl":
        create_tables()
    elif args.stage == "load":
        load_all(args.requested_date, args.start_date, args.end_date)
    else:
        run_all(args.requested_date, args.start_date, args.end_date)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
