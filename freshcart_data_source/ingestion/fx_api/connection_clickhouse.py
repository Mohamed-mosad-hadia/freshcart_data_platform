import logging
import os

from clickhouse_driver import Client
from dotenv import load_dotenv

# Loads freshcart_data_source/.env when present; real environment variables
# (e.g. set by Docker/Airflow) take precedence.
load_dotenv()

logging.basicConfig(level=logging.INFO)


def connection_clickhouse():
    try:
        client = Client(
            host=os.environ["CLICKHOUSE_HOST"],
            port=int(os.environ["CLICKHOUSE_PORT"]),
            user=os.environ["CLICKHOUSE_USER"],
            password=os.environ["CLICKHOUSE_PASSWORD"],
            database=os.environ["CLICKHOUSE_DB"],
        )
        logging.info("ClickHouse client created successfully")
        return client
    except Exception as e:
        logging.error("ClickHouse client creation failed: %s", e)
        raise
