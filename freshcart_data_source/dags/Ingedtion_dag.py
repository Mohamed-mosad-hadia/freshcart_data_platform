from datetime import datetime, timedelta

from airflow import DAG

from airflow.operators.python import PythonOperator

default_args = {
    'start_date': datetime(2026,10,18),
    'end_date': datetime(2026,10,18),
    
}
