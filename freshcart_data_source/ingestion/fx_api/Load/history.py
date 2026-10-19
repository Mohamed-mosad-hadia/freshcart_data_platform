"""Purpose: Store raw FX API rate-history responses in Bronze.
Execution Flow: Read the API key and stored rates, start at 2023-01-01 or recheck
    seven days, fetch 30-day windows, validate dates, and insert unseen payloads.
File Path: freshcart_data_source/ingestion/fx_api/Load/history.py
Dependencies and Inputs: requests, urllib3 Retry, connection_clickhouse;
    env vars FX_API_KEY (required) and FX_API_URL (default http://fx-api:8000),
    optional start_date/end_date.
Outputs: Raw response rows in bronze_fx_api.history.
"""

import json
import logging
import os
from datetime import date, datetime, timedelta
from uuid import uuid4
from zoneinfo import ZoneInfo

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


def _rates_in_payload(raw_payload, start=None, end=None):
    """Read rates for window validation and change tracking, without storing them."""
    data = json.loads(raw_payload)
    base = data["base"]
    rates = {}
    for day in data["days"]:
        rate_date = date.fromisoformat(day["rate_date"])
        if start is not None and not start <= rate_date <= end:
            raise ValueError(f"Unexpected rate_date: {rate_date}")
        for quote, rate in day["rates"].items():
            rates[(rate_date, base, quote)] = rate
    return rates


def insert_bronze_history(start_date=None, end_date=None):
    base_url = os.getenv("FX_API_URL", "http://fx-api:8000").rstrip("/")
    url = f"{base_url}/v1/rates/history"
    api_key = os.getenv("FX_API_KEY")
    if not api_key:
        raise ValueError("Set FX_API_KEY before running the history loader")
    headers = {"X-API-Key": api_key}
    batch_id = uuid4()

    client = connection_clickhouse()
    if client is None:
        raise ConnectionError("Could not connect to ClickHouse")

    try:
        if isinstance(start_date, str):
            start_date = date.fromisoformat(start_date)
        if isinstance(end_date, str):
            end_date = date.fromisoformat(end_date)

        columns = {
            name for (name,) in client.execute("""
                SELECT name FROM system.columns
                WHERE database = 'bronze_fx_api' AND table = 'history'
            """)
        }
        stored = {}

        # Existing installations may still have rows from the parsed schema.
        legacy_columns = {"rate_date", "base_currency", "quote_currency", "exchange_rate"}
        if legacy_columns <= columns:
            for rate_date, base, quote, rate in client.execute("""
                SELECT rate_date, base_currency, quote_currency,
                       argMax(exchange_rate, fetched_at)
                FROM bronze_fx_api.history
                WHERE raw_payload = ''
                GROUP BY rate_date, base_currency, quote_currency
            """):
                stored[(rate_date, base, quote)] = rate

        seen_responses = set()
        for request_start, request_end, raw_payload in client.execute("""
            SELECT request_start_date, request_end_date, raw_payload
            FROM bronze_fx_api.history
            WHERE raw_payload != ''
            ORDER BY fetched_at, batch_id
        """):
            seen_responses.add((request_start, request_end, raw_payload))
            stored.update(_rates_in_payload(raw_payload))

        # First run starts at 2023-01-01. Later runs recheck the last 7 days.
        latest = max((key[0] for key in stored), default=None)
        start = start_date or (
            max(date(2023, 1, 1), latest - timedelta(days=6))
            if latest else date(2023, 1, 1)
        )
        end = end_date or datetime.now(ZoneInfo("Africa/Cairo")).date() - timedelta(days=1)
        if start > end:
            logger.info("No new history to load")
            return

        retry_policy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods={"GET"},
            respect_retry_after_header=True,
        )
        with requests.Session() as session:
            session.mount("http://", HTTPAdapter(max_retries=retry_policy))

            while start <= end:
                window_end = min(start + timedelta(days=30), end)
                try:
                    response = session.get(
                        url,
                        headers=headers,
                        params={"start_date": start.isoformat(), "end_date": window_end.isoformat()},
                        timeout=10,
                    )
                    response.raise_for_status()
                    raw_payload = response.text
                except requests.exceptions.RequestException:
                    logger.exception("Failed to fetch history for %s to %s", start, window_end)
                    raise

                # Validate dates and count changed rates without structuring Bronze rows.
                window_rates = _rates_in_payload(raw_payload, start, window_end)
                changed_rates = sum(
                    stored.get(key) != rate for key, rate in window_rates.items()
                )

                # Identical responses for the same request window are idempotent.
                # A changed payload is kept even if only non-rate fields changed.
                response_key = (start, window_end, raw_payload)
                if response_key not in seen_responses:
                    client.execute(
                        """INSERT INTO bronze_fx_api.history
                           (batch_id, request_start_date, request_end_date, raw_payload)
                           VALUES""",
                        [(batch_id, start, window_end, raw_payload)],
                    )
                    seen_responses.add(response_key)
                    logger.info(
                        "Stored history response for %s to %s (%s new or changed rates)",
                        start, window_end, changed_rates,
                    )
                else:
                    logger.info("History response already stored for %s to %s", start, window_end)

                stored.update(window_rates)
                start = window_end + timedelta(days=1)
    finally:
        client.disconnect()


if __name__ == "__main__":
    insert_bronze_history()