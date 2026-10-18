import json
import logging
import os
import urllib.request
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator

logger = logging.getLogger(__name__)


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

    webhook_url = os.getenv("ALERT_WEBHOOK_URL") or os.getenv("SLACK_WEBHOOK_URL")
    if webhook_url:
        try:
            payload = json.dumps({"text": alert_message}).encode("utf-8")
            req = urllib.request.Request(
                webhook_url,
                data=payload,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                logger.info("Alert webhook sent successfully: HTTP %s", resp.status)
        except Exception as exc:
            logger.warning("Could not dispatch webhook alert: %s", exc)


default_args = {
    "owner": "Ahmed Nabil, Mohamed Mosaad",
    "depends_on_past": True,               # Backfill runs in chronological order
    "start_date": datetime(2026, 10, 13),  # Course start date for backfilling
    "end_date": datetime(2026, 10, 26),    # Course end date
    "retries": 3,
    "retry_delay": timedelta(minutes=1),
    # Alerting
    "email_on_failure": True,
    "email_on_retry": False,
    "email": ["alerts@freshcart.com"],
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
    pass
