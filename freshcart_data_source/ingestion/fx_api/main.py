"""Entry point for the FX API ingestion pipeline.

Run from ``freshcart_data_source`` with::

    python -m ingestion.fx_api.main

The pipeline creates the Bronze tables first, then loads health status,
currencies, daily rates, and rate history into ClickHouse.
"""

import argparse
import logging
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv

from ingestion.fx_api.DDL.currencies import currencies_table
from ingestion.fx_api.DDL.health_check import health_check_table
from ingestion.fx_api.DDL.history import history_table
from ingestion.fx_api.DDL.rates import rates_table
from ingestion.fx_api.Load.currencies import insert_bronze_currencies
from ingestion.fx_api.Load.health_check import insert_bronze_health_check
from ingestion.fx_api.Load.history import insert_bronze_history
from ingestion.fx_api.Load.rates import insert_bronze_rates

# Load the project-level environment file regardless of the current directory.
# override=False (the default) keeps variables already set by Docker/Airflow.
_env_file = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(_env_file)

logger = logging.getLogger(__name__)

CAIRO_TZ = ZoneInfo("Africa/Cairo")


def yesterday_in_cairo():
    """Return yesterday's date in Cairo as an ISO string (YYYY-MM-DD)."""
    return (datetime.now(CAIRO_TZ).date() - timedelta(days=1)).isoformat()


def initialize_tables():
    """Create or update all ClickHouse tables used by the FX API loaders."""
    for create_table in (
        health_check_table,
        currencies_table,
        rates_table,
        history_table,
    ):
        create_table()


def run_ingestion(requested_date=None, history_start=None, history_end=None):
    """Run the full FX API ingestion workflow in dependency order.

    ``requested_date`` defaults to yesterday in Cairo (the rates endpoint is
    only valid for completed days, so today's date returns 404). Callers can
    override it with an explicit ISO date when backfilling.
    """
    if requested_date is None:
        requested_date = yesterday_in_cairo()

    logger.info("Initializing FX API Bronze tables")
    initialize_tables()

    loaders = (
        ("health check", insert_bronze_health_check, ()),
        ("currencies", insert_bronze_currencies, ()),
        ("rates", insert_bronze_rates, (requested_date,)),
        ("history", insert_bronze_history, (history_start, history_end)),
    )
    for name, loader, args in loaders:
        logger.info("Starting FX API %s load", name)
        loader(*args)

    logger.info("FX API ingestion completed successfully")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run the FX API ingestion pipeline")
    parser.add_argument(
        "--rates-date",
        default=None,
        help="Date to request from the rates endpoint (YYYY-MM-DD); defaults to yesterday in Cairo",
    )
    parser.add_argument(
        "--history-start",
        help="Optional first history date (YYYY-MM-DD); defaults to the loader watermark",
    )
    parser.add_argument(
        "--history-end",
        help="Optional last history date (YYYY-MM-DD); defaults to yesterday in Cairo",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    run_ingestion(args.rates_date, args.history_start, args.history_end)


if __name__ == "__main__":
    main()