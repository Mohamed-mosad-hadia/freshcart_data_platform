'''
import os
import logging
from clickhouse_connect import get_client as Client

logging.basicConfig(level=logging.INFO)


def connection_clickhouse():
    """Create a ClickHouse Bronze client using clickhouse_connect.

    Reads configuration from environment variables (set via .env):
        CH_HOST      - ClickHouse server hostname (default: localhost)
        CH_PORT      - ClickHouse server port (default: 8123 HTTP, 9000 native)
        CH_USER      - ClickHouse user (default: freshcart_user)
        CLICKHOUSE_PASSWORD - ClickHouse password (default: freshcart_ch_pass)
        CH_DB        - Default database name (default: freshcart_dwh)
    """
    try:
        client = Client(
            host=os.getenv("CH_HOST", "localhost"),
            port=int(os.getenv("CH_PORT", "8123")),
            username=os.getenv("CH_USER", "freshcart_user"),
            password=os.getenv("CLICKHOUSE_PASSWORD", "freshcart_ch_pass"),
            database=os.getenv("CH_DB", "freshcart_dwh"),
            connect_timeout=10,
        )
        logging.info("ClickHouse client created successfully")
        return client
    except Exception as e:
        logging.error("ClickHouse client creation failed: %s", e)
    return None
'''

import os
import logging

from clickhouse_connect import get_client

from ingestion.common.clickhouse import CHClient

log = logging.getLogger(__name__)


def connection_clickhouse():
    """Create a ClickHouse client (clickhouse-connect, HTTP) wrapped so it
    also supports .execute() and .disconnect().

    Environment variables:
        CH_HOST             - hostname (default: localhost)
        CH_PORT             - HTTP port (default: 8123)
        CH_USER             - user (default: freshcart_user)
        CLICKHOUSE_PASSWORD - password (required)
        CH_DB               - database (default: freshcart_dwh)
    """
    try:
        client = get_client(
            host=os.getenv("CH_HOST", "localhost"),
            port=int(os.getenv("CH_PORT", "8123")),
            username=os.getenv("CH_USER", "freshcart_user"),
            password=os.environ["CLICKHOUSE_PASSWORD"],
            database=os.getenv("CH_DB", "freshcart_dwh"),
            connect_timeout=10,
        )
        log.info("ClickHouse client created successfully")
        return CHClient(client)
    except Exception:
        log.exception("ClickHouse client creation failed")
        return None