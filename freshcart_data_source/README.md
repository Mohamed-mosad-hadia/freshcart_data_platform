# FreshCart capstone: starter kit

This kit runs **the company** you will work for: its production database, its business
(orders arriving in real time) and its exchange-rate provider. You build the data
platform around it. **Read `docs/PROJECT_BRIEF.md` first.**

## 1. Requirements

- **Docker Desktop**, with at least **8 GB of memory** for Docker
  (Docker Desktop > Settings > Resources) and about **20 GB of free disk**
- **VS Code** (or any editor) and a **SQL tool** (DBeaver, pgAdmin, or VS Code's)
- A free **GitHub** account
- Windows: run all commands in PowerShell, inside this folder

## 2. Start the company (do it BEFORE day 1: the first start takes ~25 minutes)

Unzip the kit, open a terminal in the `freshcart-capstone` folder, then:

    docker compose up -d --build

Docker downloads Postgres and builds the company's programs (a few minutes), then the
simulator creates **two years of company history**: about 3 million orders. Follow it:

    docker compose logs -f simulator

(`Ctrl+C` stops watching; the company keeps running.)

## 3. Check that the company is ready

    docker compose exec simulator python -m simulator status

Ready when:
- **Last day started** is today
- **Latest order placed** is a few minutes ago (Cairo time)
- about **3 million orders**, and about **720 + 720 supplier files**

Run it again a few minutes later: the number of orders grows on its own.

## 4. Meet the three data sources

**The production database** (read-only account): connect your SQL tool to
`localhost`, port **5433**, database `freshcart_source`, user `analytics_reader`,
password `reader`. Or from the terminal:

    docker compose exec source-db psql -U analytics_reader -d freshcart_source -c "select * from app.orders order by placed_at desc limit 5"

**The supplier files**: open the folder `source_files/suppliers/` (`fresh/` and `general/`).

**The exchange-rate API**: open **http://localhost:8000/docs**, click **Authorize**,
enter the key `freshcart-fx-key`, then try `GET /v1/rates`.

## 5. Build your platform

- Add your services (warehouse, loaders, dbt, Airflow...) **below the company's** in
  `docker-compose.yml`. They reach the company by name: `source-db:5432`, `fx-api:8000`,
  and the supplier files through a volume on `./source_files/suppliers`.
- Add your settings at the bottom of `.env`.
- Put your code in this folder and push it to your GitHub repository.

## 6. Good to know

- **The company only runs while Docker runs.** If your laptop was off, it catches up on
  the next start: you get exactly the same data as everyone else. Give it a moment after a
  restart: `status` shows the current time once it has caught up.
- `docker compose down` stops everything and **keeps** the data.
- **Never run `docker compose down -v`** unless you want to delete the company's data
  (it would take ~25 minutes to recreate it).
- A port is already used (error "port is already allocated")? Another program uses 5433
  or 8000: stop it, or tell your instructor.
- Do not modify the company's three services or their settings in `.env`.
