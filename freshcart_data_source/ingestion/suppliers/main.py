"""Entry point for general and fresh supplier CSV ingestion.

Run from ``freshcart_data_source`` with::

    python -m ingestion.suppliers.main

Each loader creates or verifies the ClickHouse Bronze ledger and the
schema-specific tables needed by its CSV files before loading them.
"""

import argparse
import logging

from ingestion.suppliers.Load.Load_fresh_suppliers import (
    SOURCE_DIR as DEFAULT_FRESH_SOURCE_DIR,
    ingest_fresh_supplier_files,
)
from ingestion.suppliers.Load.Load_general_suppliers import (
    SOURCE_DIR as DEFAULT_GENERAL_SOURCE_DIR,
    ingest_general_supplier_files,
)

logger = logging.getLogger(__name__)


def run_ingestion(general_source_dir=DEFAULT_GENERAL_SOURCE_DIR,
                  fresh_source_dir=DEFAULT_FRESH_SOURCE_DIR):
    """Ingest the general supplier files, then the fresh supplier files."""
    summaries = {}
    for name, loader, source_dir in (
        ("general suppliers", ingest_general_supplier_files, general_source_dir),
        ("fresh suppliers", ingest_fresh_supplier_files, fresh_source_dir),
    ):
        logger.info("Starting %s load from %s", name, source_dir)
        summaries[name] = loader(source_dir)

    logger.info("Supplier ingestion completed successfully: %s", summaries)
    return summaries


def main(argv=None):
    parser = argparse.ArgumentParser(description="Ingest supplier CSV files into ClickHouse")
    parser.add_argument(
        "--general-source-dir",
        default=str(DEFAULT_GENERAL_SOURCE_DIR),
        help="Directory containing general supplier CSV files",
    )
    parser.add_argument(
        "--fresh-source-dir",
        default=str(DEFAULT_FRESH_SOURCE_DIR),
        help="Directory containing fresh supplier CSV files",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    run_ingestion(args.general_source_dir, args.fresh_source_dir)


if __name__ == "__main__":
    main()
