# FreshCart Data Platform Documentation

## Project Overview
FreshCart is a real-time grocery delivery platform operating across 6 cities. This project implements a robust Data Engineering platform to transition FreshCart from slow, manual SQL reporting on production databases to an automated, scalable data warehouse.

The platform extracts data from production PostgreSQL databases, external CSV supplier files, and a live FX Rate API, orchestrating the pipeline through Airflow. It processes data incrementally, cleans it into silver layers, and models it into a star schema gold layer for business analytics.

## Architecture
```
 Source DB ──┐                                                  ┌─► Dashboards / SQL
 CSV Files ──┼─► Python Extract & Load ─► BRONZE ─► dbt ─► SILVER ─► dbt ─► GOLD
 FX API    ──┘                          (Raw)          (Clean)        (Star Schema)
                     All orchestrated by Airflow; Everything runs in Docker
```

## Technology Stack
- **Orchestration**: Apache Airflow
- **Data Modeling**: dbt (data build tool)
- **Database**: PostgreSQL (Warehouse)
- **Data Extraction**: Python
- **Environment/Infrastructure**: Docker, Docker Compose

## Project Components
1. **Source Connectors (Python)**:
   - **Database Loader**: Extracts data from PostgreSQL (`freshcart_source`).
   - **Supplier Loader**: Processes incoming CSV stock files from suppliers.
   - **FX API Loader**: Fetches exchange rates to convert local currencies to USD.
2. **dbt Models**:
   - **Bronze**: Raw data ingest, preserves source integrity.
   - **Silver**: Data cleaning, deduplication, and anomaly flagging.
   - **Gold**: Star schema models answering core business questions (revenue, orders, stockouts, price history).
3. **Airflow DAG**:
   - Automated nightly processing of daily data batches.
   - Handles dependency management, retries, sensors (for file availability), and alerts.

## Getting Started

### Starting the Project
To initialize and run the entire environment:
```bash
docker-compose up -d --build
```
*Note: The initial start-up may take approximately 25 minutes.*

### Managing the Project
- **View Simulator Status**:
  ```bash
  docker-compose exec simulator python -m simulator status
  ```
- **Access FX API Documentation**: 
  Open `http://localhost:8000/docs` in your browser. Use the key: `freshcart-fx-key`.
- **View Simulator Logs**:
  ```bash
  docker-compose logs -f simulator
  ```

### Stopping the Project
To stop the services while preserving your data volumes:
```bash
docker-compose down
```

## Knowledge Retrieval
This project includes a knowledge graph (`graphify-out/`) that serves as an RAG system for codebase exploration. Use it to find architectural relationships and project context:
- Run `/graphify query "<question>"` to trace data flows or explain components.
- Refer to `graphify-out/GRAPH_REPORT.md` for core system abstractions.
