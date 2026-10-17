"""Ingest fresh supplier CSV files into schema-specific Bronze tables.

Validate each file, reuse the ClickHouse connection, create matching tables,
resume missing rows, and record completed files so reruns do not duplicate data.
Run with: python -m ingestion.suppliers.Load_suppliers
"""

import csv
import hashlib
import io
import logging
from pathlib import Path
from uuid import uuid4

from ingestion.fx_api.connection_clickhouse import connection_clickhouse
from ingestion.suppliers.DDL_suppliers import (
    BRONZE_DB,
    LEDGER_TABLE,
    ensure_data_table,
    ensure_ledger,
    quote_identifier,
    validate_header,
)

logger = logging.getLogger(__name__)

SOURCE_DIR = Path(__file__).resolve().parents[2] / "source_files" / "suppliers" / "fresh"
INSERT_BATCH_SIZE = 10_000


def read_csv(path):
    """Return the ordered header, unconverted field strings, and file hash."""
    content = path.read_bytes()
    digest = hashlib.sha256(content).hexdigest()
    reader = csv.reader(io.StringIO(content.decode("utf-8-sig"), newline=""), strict=True)
    header = next(reader, None)
    validate_header(header)
    rows = []
    for row in reader:
        if len(row) != len(header):
            raise ValueError(
                f"{path.name}: CSV record ending at line {reader.line_num} has "
                f"{len(row)} fields; expected {len(header)}"
            )
        rows.append(tuple(row))
    return tuple(header), rows, digest


def _existing_row_numbers(client, table, filename, digest):
    sql = f"""
        SELECT source_row_number
        FROM {quote_identifier(BRONZE_DB)}.{quote_identifier(table)}
        WHERE source_file = %(filename)s AND file_sha256 = %(digest)s
    """
    return {number for (number,) in client.execute(
        sql, {"filename": filename, "digest": digest}
    )}


def _verify_loaded_rows(client, table, filename, digest, expected):
    sql = f"""
        SELECT count(), uniqExact(source_row_number)
        FROM {quote_identifier(BRONZE_DB)}.{quote_identifier(table)}
        WHERE source_file = %(filename)s AND file_sha256 = %(digest)s
    """
    count, distinct = client.execute(sql, {"filename": filename, "digest": digest})[0]
    if count != expected or distinct != expected:
        raise RuntimeError(
            f"{filename}: expected {expected} unique Bronze rows, "
            f"found {count} rows and {distinct} distinct row numbers"
        )


def _load_file(client, path, batch_id, table_cache):
    header, rows, digest = read_csv(path)
    if header not in table_cache:
        table_cache[header] = ensure_data_table(client, header)
    table, schema_hash = table_cache[header]
    ledger = f"{quote_identifier(BRONZE_DB)}.{quote_identifier(LEDGER_TABLE)}"
    key = {"filename": path.name, "digest": digest}
    completed = client.execute(
        f"""SELECT row_count FROM {ledger}
            WHERE source_file = %(filename)s AND file_sha256 = %(digest)s
            LIMIT 1""",
        key,
    )
    if completed:
        if completed[0][0] != len(rows):
            raise RuntimeError(f"{path.name}: ledger row count disagrees with CSV")
        _verify_loaded_rows(client, table, path.name, digest, len(rows))
        logger.info("Skipped already ingested file %s", path.name)
        return 0, True, table

    existing = _existing_row_numbers(client, table, path.name, digest)
    insert_columns = [*header, "batch_id", "source_file", "file_sha256", "source_row_number"]
    names = ", ".join(quote_identifier(name) for name in insert_columns)
    query = f"INSERT INTO {quote_identifier(BRONZE_DB)}.{quote_identifier(table)} ({names}) VALUES"
    pending = []
    inserted = 0
    for number, row in enumerate(rows, 1):
        if number in existing:
            continue
        pending.append((*row, batch_id, path.name, digest, number))
        if len(pending) == INSERT_BATCH_SIZE:
            client.execute(query, pending)
            inserted += len(pending)
            pending.clear()
    if pending:
        client.execute(query, pending)
        inserted += len(pending)

    _verify_loaded_rows(client, table, path.name, digest, len(rows))
    client.execute(
        f"""INSERT INTO {ledger}
            (source_file, file_sha256, schema_hash, row_count, batch_id) VALUES""",
        [(path.name, digest, schema_hash, len(rows), batch_id)],
    )
    logger.info("Ingested %s: %s new rows into %s.%s", path.name, inserted, BRONZE_DB, table)
    return inserted, False, table


def ingest_fresh_supplier_files(source_dir=SOURCE_DIR):
    """Ingest all CSVs in the fresh supplier folder and report file counts."""
    source_dir = Path(source_dir)
    if not source_dir.is_dir():
        raise FileNotFoundError(f"Supplier CSV directory not found: {source_dir}")
    files = sorted(source_dir.glob("*.csv"))
    if not files:
        raise FileNotFoundError(f"No CSV files found in {source_dir}")

    client = connection_clickhouse()
    if client is None:
        raise ConnectionError("Could not connect to ClickHouse")

    batch_id = uuid4()
    summary = {"files": len(files), "ingested": 0, "skipped": 0, "rows": 0, "failed": 0}
    table_cache = {}
    failures = []
    try:
        ensure_ledger(client)
        for path in files:
            try:
                inserted, skipped, _ = _load_file(client, path, batch_id, table_cache)
                summary["skipped" if skipped else "ingested"] += 1
                summary["rows"] += inserted
            except Exception:
                summary["failed"] += 1
                failures.append(path.name)
                logger.exception("Failed to ingest %s", path)
    finally:
        client.disconnect()

    logger.info("Supplier Bronze ingestion summary: %s", summary)
    if failures:
        examples = ", ".join(failures[:10])
        raise RuntimeError(f"Failed to ingest {len(failures)} CSV files: {examples}")
    return summary


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    ingest_fresh_supplier_files()
