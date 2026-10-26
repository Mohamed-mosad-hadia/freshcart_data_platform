import json
import logging
import os
import urllib.request
from pathlib import Path
from datetime import datetime, timedelta
from airflow import DAG
from airflow.models import Variable
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.sensors.python import PythonSensor
from airflow.utils.email import send_email

# Import the ingestion functions
from ingestion.database import run_database_ingestion
from ingestion.fx_api import run_ingestion
from ingestion.suppliers import run_ingestion as run_supplier_ingestion

logger = logging.getLogger(__name__)

SUPPLIER_DIR = Path(os.getenv("SUPPLIER_DIR", "/opt/airflow/project/source_files/suppliers"))
SETTLE_SECONDS = 30  # ignore files modified in the last 30s (may still be written)

def task_failure_alert(context):
    """Callback executed when a task fails permanently (after retries)."""
    ti = context.get("task_instance")
    dag_id = ti.dag_id if ti else context.get("dag").dag_id
    task_id = ti.task_id if ti else "unknown"
    execution_date = context.get("ds") or context.get("logical_date")
    exception = context.get("exception")
    log_url = getattr(ti, "log_url", "N/A")
    try_number = getattr(ti, "try_number", "N/A")

    alert_message = (
        f"🚨 [AIRFLOW ALERT] Task Failed Permanently!\n"
        f"• DAG: {dag_id}\n"
        f"• Task: {task_id}\n"
        f"• Execution Date: {execution_date}\n"
        f"• Try Number: {try_number}\n"
        f"• Error: {exception}\n"
        f"• Log URL: {log_url}"
    )
    logger.error(alert_message)

    # Send Gmail Alert
    alert_email_to = (
        os.getenv("ALERT_EMAIL_TO")
        or Variable.get("alert_email_to", default=None)
    )
    if alert_email_to:
        subject = f"🚨 [Airflow Alert] Task Failed: {dag_id}.{task_id} ({execution_date})"
        html_body = f"""
        <div style="font-family: Arial, sans-serif; padding: 12px; border: 1px solid #ddd; border-radius: 6px;">
            <h2 style="color: #d9534f; margin-top: 0;">Airflow Task Failure Alert</h2>
            <p>A task has permanently failed after retries:</p>
            <ul>
                <li><b>DAG:</b> {dag_id}</li>
                <li><b>Task:</b> {task_id}</li>
                <li><b>Execution Date:</b> {execution_date}</li>
                <li><b>Try Number:</b> {try_number}</li>
            </ul>
            <p><b>Error Details:</b></p>
            <pre style="background: #f8f8f8; padding: 10px; border: 1px solid #ccc; color: #a94442;">{exception}</pre>
            <p><a href="{log_url}" style="background-color: #0275d8; color: white; padding: 8px 14px; text-decoration: none; border-radius: 4px;">View Full Logs</a></p>
        </div>
        """
        try:
            send_email(to=alert_email_to, subject=subject, html_content=html_body)
            logger.info("Alert email successfully dispatched to %s", alert_email_to)
        except Exception as exc:
            logger.warning("Could not dispatch email alert via Gmail: %s", exc)

def supplier_files_ready():
    """Return True once at least one settled supplier CSV exists."""
    if not SUPPLIER_DIR.is_dir():
        logger.info("Supplier directory not found yet: %s", SUPPLIER_DIR)
        return False

    now = datetime.now().timestamp()    
    ready = [
        p for p in SUPPLIER_DIR.rglob("*.csv")
        if p.is_file() and now - p.stat().st_mtime > SETTLE_SECONDS
    ]
    logger.info("Found %d settled supplier CSV file(s) under %s", len(ready), SUPPLIER_DIR)
    return bool(ready)

default_args = {
    "owner": "Ahmed Nabil, Mohamed Mosaad",
    "depends_on_past": True,               # Backfill runs in chronological order

    "start_date": datetime(2026, 10, 13),  # Course start date for backfilling
    "retries": 3,
    "retry_delay": timedelta(minutes=1),
    # Alerting
    "email_on_failure": True,
    "email_on_retry": False,
    "email": [os.getenv("ALERT_EMAIL_TO", "alerts@freshcart.com")],
    "on_failure_callback": task_failure_alert,
}

with DAG(
    dag_id="ingestion_dag",
    default_args=default_args,
    description="Daily ingestion pipeline with backfill and failure alerts",
    schedule="@daily",
    catchup=True,          # Automatically backfills past days
    max_active_runs=1,     # 1 run at a time to prevent race conditions during backfill
    tags=["freshcart", "Ingestion"],
) as dag:

    Database_Ingestion_dag = PythonOperator(
        task_id="Database_Ingestion_dag",
        python_callable=run_database_ingestion,
        op_kwargs={
            "mode": "incremental",
            "lookback": 2
        },
    )
    Fx_api_ingestion_dag = PythonOperator(
        task_id="Fx_api_ingestion_dag",
        python_callable=run_ingestion,
    )

    Wait_for_supplier_files = PythonSensor(
        task_id="Wait_for_supplier_files",
        python_callable=supplier_files_ready,
        depends_on_past=False,
        mode="reschedule",                    # frees the worker slot between checks
        poke_interval=60,                     # check every minute
        timeout=60 * 60,                      # give up after 1 hour
        retries=0,                            # the timeout already covers waiting
    )

    Supplier_Ingestion_dag = PythonOperator(
        task_id="Supplier_Ingestion_dag",
        python_callable=run_supplier_ingestion,
    )

    # Database and FX run independently; suppliers wait for their files.
    Wait_for_supplier_files >> Supplier_Ingestion_dag
    [Database_Ingestion_dag, Fx_api_ingestion_dag]