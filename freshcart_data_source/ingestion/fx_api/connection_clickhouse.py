from clickhouse_driver import Client

import logging
logging.basicConfig(level=logging.INFO)

def connection_clickhouse(): 
    try: 
        client = Client(
            host='localhost',
            port=9000,
            user='freshcart_user',
            password='freshcart_ch_pass',
            database='freshcart_dwh',
        )
        logging.info("ClickHouse client created successfully")
        return client
    except Exception as e:
        logging.error("ClickHouse client creation failed: %s", e)