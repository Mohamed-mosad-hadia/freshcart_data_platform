# FreshCart Data Platform Architecture

## Overview

The FreshCart capstone project implements a comprehensive data platform that processes real-time order data and exchange-rate information. The system extracts data from multiple sources (production database, supplier files, and external APIs), transforms it through various layers, and delivers actionable insights via a data warehouse.

## System Components

### Core Infrastructure

#### 1. The "Company" Services (Non-negotiable)
These three services represent the core business systems that your data platform will serve:

- **source-db** (PostgreSQL, port 5433): Production database containing orders, customers, and products
- **simulator**: Generates realistic test data (~3M orders over 2 years) to simulate business operations
- **fx-api** (FastAPI): External exchange-rate API providing currency conversion rates

#### 2. Data Platform Components (Your responsibility to build)

Your task is to add services **below** these core services in `docker-compose.yml`. These services connect to the company by name:

- `source-db:5432` - PostgreSQL database connection
- `fx-api:8000` - Exchange-rate API endpoint  
- `./source_files/suppliers/` - Directory containing supplier CSV files

## Data Flow Pipeline

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   source-db     │    │   simulator      │    │   fx-api        │
│   (orders)      │    │   (data gen)     │    │   (rates)       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
       │                       │                       │
       └───────────────────────┼───────────────────────┘
                               ▼
                   ┌──────────────────┐
                   │   Your Platform  │
                   │  (to be built)   │
                   └──────────────────┘
                               │
             ┌───────────────────┼───────────────────┐
             ▼                   ▼                   ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │ Warehouse   │    │ Loaders     │    │ Orchestrator│
    │ (ClickHouse)│    │ (Airflow)    │    │ (Airflow)    │
    └─────────────┘    └─────────────┘    └─────────────┘
             │                   │                   │
             └───────────────────┴───────────────────┘
                               ▼
                   ┌──────────────────┐
                   │   dbt Models     │
                   │  (silver/gold)   │
                   └──────────────────┘
                               ▼
                   ┌──────────────────┐
                   │   Analytics      │
                   │   (end users)    │
                   └──────────────────┘
```

## Data Ingestion Modules

### 1. Database Ingestion (ingestion/database/Ingest_app.py)
Functions for reading and processing data from the production database:

- **extract()**: Reads PostgreSQL tables within specified date ranges
- **write()**: Writes processed data to ClickHouse
- **cairo_midnight_utc()**: Handles timezone conversions (Cairo time)
- **run_database_ingestion()**: Orchestrates full database ingestion

### 2. Supplier File Ingestion (ingestion/suppliers/)
Processes supplier CSV files from both fresh and general suppliers:

#### DDL (ingestion/suppliers/DDL/)
- **DDL_general_suppliers.py**: Creates bronze tables for general supplier data
- **DDL_fresh_suppliers.py**: Creates bronze tables for fresh supplier data

**Key functionality:**
- Validates CSV headers and schema
- Creates ClickHouse tables with consistent structure
- Handles duplicate prevention and metadata tracking

#### Load (ingestion/suppliers/Load/)
- **Load_general_suppliers.py**: Loads general supplier CSV files
- **Load_fresh_suppliers.py**: Loads fresh supplier CSV files

**Key functionality:**
- Reads CSV files with header validation
- Inserts data into bronze tables with metadata tracking
- Handles duplicate detection and batch processing

### 3. FX API Ingestion (ingestion/fx_api/)
Processes exchange-rate data from the external FX API:

#### DDL (ingestion/fx_api/DDL/)
- **rates.py**: Creates bronze rates table
- **history.py**: Creates bronze history table  
- **currencies.py**: Creates bronze currencies table
- **health_check.py**: Creates health check tracking table

#### Load (ingestion/fx_api/Load/)
- **rates.py**: Loads current rate data
- **history.py**: Loads historical rate data with windowed requests
- **health_check.py**: Tracks API health and performance

#### Connection (ingestion/fx_api/connection_clickhouse.py)
Creates ClickHouse connections using environment variables

### 4. Common Utilities (ingestion/common/)
Shared functionality used across ingestion modules:

- **clickhouse.py**: CHClient class providing ClickHouse operations with INSERT optimization

## Data Processing Pipeline

### Bronze Layer (Raw Data)
- All ingestion modules write to ClickHouse `bronze_*` databases
- Raw data with metadata (batch_id, timestamps, source)
- Schemas defined in DDL modules

### Silver Layer (dbt models)
- Transform bronze data into clean, structured formats
- Key models include:
  - **silver_fx_api/rates.sql**: Current exchange rates
  - **silver_fx_api/history.sql**: Historical exchange rate trends
  - **silver_app/products.sql**, **silver_app/customers.sql**: Product and customer data
  - **silver_app/orders.sql**: Order transaction data

### Gold Layer (Analytical Models)
- Business-ready analytical models in `freshcart_pipline/models/gold/`
- **dim_product_price_history.sql**: Product price history (SCD Type 2)
- Various dimensional models for analytics

## Airflow Orchestration

### DAG Structure (dags/Ingedtion_dag.py)
- **bronze-loaded**: Triggers when new supplier files appear
- **database-ingestion**: Scheduled to run at regular intervals
- **fx-api-ingestion**: Runs FX API data collection

### Services Added to docker-compose.yml
- **airflow-worker**: Executes DAG tasks
- **airflow-scheduler**: Manages DAG scheduling
- **airflow-dag-processor**: Processes DAG files
- **airflow-init**: Initializes Airflow metadata
- **airflow-apiserver**: Provides Airflow API access
- **airflow-triggerer**: Triggers DAG runs
- **flower**: Airflow monitoring dashboard

## Configuration

### Environment Variables (.env)
All services use environment variables for configuration:

```bash
# Database
SOURCE_DB_USER=analytics_reader
SOURCE_DB_PASSWORD=reader

# ClickHouse  
CLICKHOUSE_PASSWORD=freshcart_ch_pass
CH_HOST=localhost
CH_PORT=8123
CH_USER=freshcart_user
CH_DB=freshcart_dwh

# FX API
FX_API_KEY=freshcart-fx-key
FX_API_URL=http://fx-api:8000

# Simulator
ORDERS_PER_DAY=720
N_CUSTOMERS=100
N_PRODUCTS=50

# Airflow
AIRFLOW_UID=50000
AIRFLOW_JWT_SECRET=your-secret-key
AIRFLOW_FERNET_KEY=your-fernet-key
```

### Docker Compose Services
Key services and their purposes:

- **clickhouse**: ClickHouse data warehouse (freshcart_dwh database)
- **airflow-worker**: Executes ingestion tasks
- **airflow-scheduler**: Manages DAG schedules
- **airflow-init**: Initializes Airflow infrastructure

## Deployment Instructions

### 1. Start the Company
```bash
docker compose up -d --build
docker compose logs -f simulator  # Follow data generation
```

### 2. Verify Setup
```bash
docker compose exec simulator python -m simulator status
```

### 3. Build Your Platform
Add your services below the company's services in `docker-compose.yml`:

1. Add ClickHouse service (if not already present)
2. Add Airflow services for orchestration
3. Add your custom loaders/processors as needed
4. Update `.env` with your configuration
5. Build and start: `docker compose up -d --build`

### 4. Monitor
- Check logs: `docker compose logs -f <service-name>`
- Airflow UI: http://localhost:8080
- Flower dashboard: http://localhost:5555

## Development Workflow

### Local Development
1. Make changes to your ingestion modules in `ingestion/`
2. Test locally using Python directly
3. Commit changes and push to GitHub
4. Docker Compose will rebuild and restart services

### Data Flow Monitoring
- Bronze layer: Check ClickHouse tables directly
- Silver layer: View dbt model outputs
- Gold layer: Query analytical models

## Architecture Notes

### Data Governance
- All data movement is tracked with batch IDs and timestamps
- Source attribution is maintained throughout the pipeline
- Duplicate prevention ensures idempotent operations

### Scalability
- Airlfow handles orchestration of large data volumes
- ClickHouse provides fast analytical queries
- Docker ensures consistent deployment across environments

### Monitoring
- Comprehensive logging in all services
- Airflow provides operational visibility
- Health checks ensure system reliability

## Key Technologies

- **Infrastructure**: Docker Compose, PostgreSQL, ClickHouse, FastAPI
- **Orchestration**: Apache Airflow with Celery executor
- **Data Processing**: Python, dbt, SQL
- **Monitoring**: Logging, Airflow UI, Flower dashboard

## Next Steps

1. Add ClickHouse service to docker-compose.yml
2. Implement missing ingestion modules
3. Set up Airflow orchestration
4. Build dbt models for silver layer
5. Create analytical models in gold layer
6. Test end-to-end data flow
7. Deploy and monitor production system

This architecture provides a scalable foundation for building a comprehensive data platform around the FreshCart business systems.