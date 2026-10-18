"""Purpose: Store raw FX API rates responses in Bronze.
Execution Flow: Parse the requested date, generate a batch ID, request /v1/rates
    with retries, then insert the date and response text into ClickHouse.
File Path: freshcart_data_source/ingestion/fx_api/Load/rates.py
Dependencies and Inputs: requests, urllib3 Retry, connection_clickhouse;
    local API, X-API-Key header, and requested_date (default 2023-01-01).
Outputs: A row in bronze_fx_api.rates.
"""

import logging
import os
from datetime import date
from uuid import uuid4

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


FX_API_BASE_URL = os.environ["FX_API_BASE_URL"].rstrip("/")

def insert_bronze_rates(requested_date="2023-01-01"):
    url = f"{FX_API_BASE_URL}/v1/rates"
    headers = {"X-API-Key": os.environ["FX_API_KEY"]}
    if isinstance(requested_date, str):
        requested_date = date.fromisoformat(requested_date)
    batch_id = uuid4()

    try:
        retry_policy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods={"GET"},
            respect_retry_after_header=True,
        )
        with requests.Session() as session:
            session.mount("http://", HTTPAdapter(max_retries=retry_policy))
            response = session.get(
                url,
                params={"date": requested_date.isoformat()},
                headers=headers,
                timeout=10,
            )
        response.raise_for_status()
        raw_payload = response.text
    except requests.exceptions.RequestException:
        logger.exception("Rates API request failed")
        raise

    try:
        client = connection_clickhouse()
        client.execute(
            "INSERT INTO bronze_fx_api.rates (batch_id, requested_date, raw_payload) VALUES",
            [(batch_id, requested_date, raw_payload)],
        )
        logger.info("Inserted rates payload for %s in batch %s", requested_date, batch_id)
    except Exception:
        logger.exception("Failed to insert data into bronze_fx_api.rates")
        raise


if __name__ == "__main__":
    insert_bronze_rates()
