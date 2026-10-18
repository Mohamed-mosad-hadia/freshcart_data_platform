"""Purpose: Store raw FX API health-check responses in Bronze.
Execution Flow: When called, generate a batch ID, request /health with retries,
    then insert the response text into ClickHouse.
File Path: freshcart_data_source/ingestion/fx_api/Load/health_check.py
Dependencies and Inputs: requests, urllib3 Retry, connection_clickhouse;
    local API at /health and its X-API-Key header.
Outputs: A row in bronze_fx_api.health_check.
"""

import logging
from uuid import uuid4

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from ingestion.fx_api.connection_clickhouse import connection_clickhouse

logger = logging.getLogger(__name__)


def insert_bronze_health_check():
    url = "http://localhost:8000/health"
    headers = {"X-API-Key": "freshcart-fx-key"}
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
        logger.exception("API request failed")
        raise

    try:
        client = connection_clickhouse()
        client.execute(
            "INSERT INTO bronze_fx_api.health_check (batch_id, raw_payload) VALUES",
            [(batch_id, raw_payload)],
        )
        logger.info("Inserted health check payload for batch %s", batch_id)
    except Exception:
        logger.exception("Failed to insert health check data into bronze_fx_api.health_check")
        raise
