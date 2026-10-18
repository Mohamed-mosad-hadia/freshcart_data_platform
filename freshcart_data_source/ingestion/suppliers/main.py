"""Purpose: Single entry point for the supplier CSV Bronze ingestion.
Execution Flow: Each load function creates its own Bronze tables (DDL) on demand,
    then ingests the CSV files. Airflow calls load_fresh() and load_general()
    as separate tasks; the CLI runs them locally.
File Path: freshcart_data_source/ingestion/suppliers/main.py
Dependencies and Inputs: ingestion.suppliers.Load.*; CSVs in
    source_files/suppliers/{fresh,general}; ClickHouse running.
Outputs: Supplier tables and ledger in the supplier Bronze databases.
Usage (run from freshcart_data_source/):
    python -m ingestion.suppliers.main --source all
    python -m ingestion.suppliers.main --source fresh
    python -m ingestion.suppliers.main --source general
"""

import argparse
import logging

from ingestion.suppliers.Load.Load_fresh_suppliers import ingest_fresh_supplier_files
from ingestion.suppliers.Load.Load_general_suppliers import ingest_general_supplier_files

logger = logging.getLogger(__name__)


def load_fresh():
    return ingest_fresh_supplier_files()


def load_general():
    return ingest_general_supplier_files()


def run_all():
    return {"fresh": load_fresh(), "general": load_general()}


def main():
    parser = argparse.ArgumentParser(description="Supplier CSV Bronze ingestion")
    parser.add_argument("--source", choices=("fresh", "general", "all"), default="all")
    args = parser.parse_args()

    if args.source == "fresh":
        load_fresh()
    elif args.source == "general":
        load_general()
    else:
        run_all()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
