"""Build silver and gold with dbt (Cosmos) after the nightly Bronze load.

Scheduled on the asset published by ingestion_dag's last task (Bronze_loaded), so dbt only
runs after the three sources were loaded successfully. Each dbt model becomes an Airflow
task followed by its tests; a failing (error) test stops the models downstream of it.

Build-time requirements (e.g. in Dockerfile.airflow or CI), run from the dbt project dir:
    dbt deps
    dbt parse --target airflow   # writes target/manifest.json
Re-run `dbt parse` whenever the dbt project changes, otherwise the DAG shows stale nodes.
"""

from datetime import datetime, timedelta
from pathlib import Path

from airflow.sdk import Asset
from cosmos import (
    DbtDag,
    ExecutionConfig,
    LoadMode,
    ProfileConfig,
    ProjectConfig,
    RenderConfig,
    TestBehavior,
)

DBT_PROJECT = Path("/opt/airflow/project/freshcart_pipline")
DBT_MANIFEST = DBT_PROJECT / "target" / "manifest.json"  # pre-built, see docstring
DBT_EXECUTABLE = "/opt/airflow/dbt_venv/bin/dbt"  # isolated venv from Dockerfile.airflow

# Same asset as in Ingedtion_dag.py (published by its Bronze_loaded task)
BRONZE_LOADED = Asset("freshcart_bronze_daily_load")

dbt_dag = DbtDag(
    dag_id="dbt_dag",
    project_config=ProjectConfig(
        dbt_project_path=DBT_PROJECT,
        manifest_path=DBT_MANIFEST,
        # dbt packages (dbt_utils, dbt_expectations, codegen, dbt_date) are installed
        # at image build time, so no `dbt deps` at parse time or in every task.
        # If your Cosmos version supports it, also set install_dbt_deps=False here.
    ),
    profile_config=ProfileConfig(
        profile_name="freshcart_pipeline",
        target_name="airflow",
        profiles_yml_filepath=DBT_PROJECT / "profiles.yml",
    ),
    execution_config=ExecutionConfig(dbt_executable_path=DBT_EXECUTABLE),
    render_config=RenderConfig(
        # Read nodes from the pre-built manifest: no `dbt ls` subprocess at import time,
        # so the DAG file imports in well under the 30s DagBag timeout.
        load_method=LoadMode.DBT_MANIFEST,
        test_behavior=TestBehavior.AFTER_EACH,  # each model's tests right after it
        select=["path:models"],  # silver + gold models and their tests (no analyses)
    ),
    # No install_deps: `dbt deps` ran at build time (saves ~17s per task).
    operator_args={},
    schedule=[BRONZE_LOADED],
    start_date=datetime(2026, 10, 13),
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "Ahmed Nabil, Mohamed Mosaad",
        "retries": 2,
        "retry_delay": timedelta(minutes=1),
    },
    description="dbt silver + gold build, triggered after the nightly Bronze load",
    tags=["freshcart", "dbt"],
)