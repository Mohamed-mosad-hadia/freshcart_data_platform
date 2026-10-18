"""
Purpose:
    Store raw FX API currencies responses in Bronze.
Execution Flow:
    Generate a batch ID, request /v1/currencies with retries, then
    insert the response text into ClickHouse.
File Path:
    freshcart_data_source/ingestion/fx_api/Load/currencies.py
Dependencies and Inputs: 
    requests, urllib3 Retry, connection_clickhouse;
    local API at /v1/currencies and its X-API-Key header.
Outputs: A row in bronze_fx_api.currencies.
"""

import logging
import os
from uuid import uuid4

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)

FX_API_BASE_URL = os.environ["FX_API_BASE_URL"].rstrip("/")


def insert_bronze_currencies():
    url = f"{FX_API_BASE_URL}/v1/currencies"
    headers = {"X-API-Key": os.environ["FX_API_KEY"]}
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
            response = session.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        raw_payload = response.text
    except requests.exceptions.RequestException:
        logger.exception("Currencies API request failed")
        raise

    try:
        client = connection_clickhouse()
        client.execute(
            "INSERT INTO bronze_fx_api.currencies (batch_id, raw_payload) VALUES",
            [(batch_id, raw_payload)],
        )
        logger.info("Inserted currencies payload for batch %s", batch_id)
    except Exception:
        logger.exception("Failed to insert data into bronze_fx_api.currencies")
        raise


if __name__ == "__main__":
    insert_bronze_currencies()
