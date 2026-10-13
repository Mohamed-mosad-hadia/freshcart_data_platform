# DataCraft Intermediate Track: Capstone Project

## FreshCart: build the data platform of a real-time grocery-delivery company

**Project dates:** Tuesday 13 October -> Monday 26 October 2026 (two weeks)

You have just joined **FreshCart** as its data engineering team. FreshCart delivers
groceries in under an hour from 6 stores: Cairo (Maadi, Nasr City), Giza (Sheikh
Zayed), Alexandria (Smouha), Riyadh (Olaya) and Dubai (Marina). It has been in business
for two years: about **3 million orders** so far, and around **5,000 new orders every day**.

Management has no reliable numbers. Finance runs slow reports directly on the
production database, and nobody can answer simple questions like "how much did each
store earn yesterday, in US dollars?". **Your job: build the company's data platform.**

**This company is alive.** Its data is created in real time on the Cairo clock: while the
company is running, an order placed at 14:35 appears in the database at 14:35. If your
laptop is off, the company catches up as soon as you restart it: the missed orders appear
at once, with their real times. Every day there is new data, and, as in any real company,
things will change while you work.

Everything is free and runs on your laptop with Docker.

---

## 1. What you are given: the company

The starter kit (see `README.md`) runs FreshCart's systems. **You do not change them**:
you extract data from them, like a data engineer at a real company.

### Source 1: the production database (PostgreSQL)

| | |
|---|---|
| From your laptop | `localhost:5433`, database `freshcart_source` |
| From a container | `source-db:5432` |
| Your account | `analytics_reader` (read-only), password in `.env` (`SOURCE_READER_PASSWORD`) |

Schema `app`:

| Table | Content |
|---|---|
| `stores` | store_id, store_name, city, country, currency (EGP, SAR, AED), opened_at |
| `customers` | customer_id, first_name, last_name, email, phone, city, signup_date |
| `products` | product_id, product_name, category, unit_price_usd (current catalogue price), is_active |
| `product_prices` | every catalogue price: product_id, unit_price_usd, valid_from |
| `orders` | order_id, customer_id, store_id, order_status (`placed`, `delivered`, `cancelled`), placed_at, delivered_at |
| `order_items` | order_item_id, order_id, product_id, quantity, unit_price, line_amount (store currency) |
| `payments` | payment_id, order_id, payment_method (`card`, `wallet`, `cash`), payment_status (`paid`, `refunded`), amount, paid_at |

Every table has `created_at` and `updated_at`. **Rows change after they are created**:
an order goes from `placed` to `delivered` or `cancelled`, customers update their
profile, prices change, refunds arrive days later.

### Source 2: supplier stock files (CSV)

Two suppliers send an end-of-day stock file (units on the shelf at 22:00, per product and
store) into the folder `source_files/suppliers/`:

| Supplier | File | Arrives |
|---|---|---|
| FRESH (fruits & vegetables, dairy, bakery, meat & fish) | `fresh/fresh_stock_YYYY-MM-DD.csv` | every day at 22:00 |
| GENERAL (everything else) | `general/GENERAL_STOCK_YYYYMMDD.csv` | every day at 23:30, but sometimes late (the next morning) |

The two suppliers do not use the same format. Look at the files.

### Source 3: the exchange-rate API (HTTP)

FreshCart sells in EGP, SAR and AED; management reports in **USD**. The company
subscribes to an external rate provider:

| | |
|---|---|
| From your laptop | `http://localhost:8000` (interactive docs: `/docs`) |
| From a container | `http://fx-api:8000` |
| API key | header `X-API-Key`, value in `.env` (`FX_API_KEY`) |

| Endpoint | Returns |
|---|---|
| `GET /v1/rates?date=YYYY-MM-DD` | the rates valid on that day (units of currency per 1 USD) |
| `GET /v1/rates/history?start_date=...&end_date=...` | every published day of a period (max 31 days per call) |
| `GET /v1/currencies` | the currencies |

It behaves like a real third-party provider: rates are published on business days
(Sunday to Thursday) at 16:00 Cairo time; it limits how many calls you can make per
minute; and it is not 100% reliable. Read its answers carefully.

### Known data quality issues

Finding them is part of the job. Stakeholders have mentioned a few:

- "Our QA team creates test accounts in production."
- "Some customers seem to have two accounts."
- "Phone numbers are typed in every possible way."
- "One supplier's file is always a headache."

There are more.

---

## 2. What you build

```
 source DB ──┐                                                  ┌─► dashboards / SQL
 CSV files ──┼─► Python extract & load ─► BRONZE ─► dbt ─► SILVER ─► dbt ─► GOLD
 FX API    ──┘                          (raw)          (clean)        (star schema)
                     all orchestrated by Airflow, every night; everything in Docker
```

### 2.1 Docker
- Your whole platform runs in containers **in the same `docker-compose.yml`** as the
  company (add your services below the company's).
- One command starts everything. Passwords live in `.env`, never in your code.

### 2.2 The warehouse (PostgreSQL)
- A **separate** Postgres container: never run analytics on the production database.
- Layers as schemas: **bronze and silver per source system** (e.g. `bronze_app`,
  `bronze_suppliers`, `bronze_fx`), **gold per business topic**.

### 2.3 Extract & load (Python): sources -> bronze
- **Initial full load**: all the history, once.
- **Then incremental, one business day (Cairo time) at a time**: only what was created
  or changed that day.
- **Idempotent**: loading the same day twice must never create duplicates.
- Bronze keeps the data **as received** (no cleaning), with where/when it was loaded.
- Supplier files: load each file once; late files must still be loaded.
- API: survive its failures and its limits.
- **Load a day only when the source has finished it**: after a restart, the company first
  catches up the missed hours, and a day loaded in the middle of that would be incomplete.

### 2.4 dbt: bronze -> silver -> gold
- **Silver**: one clean, trustworthy table per source table (latest version of each row,
  standard formats, flags for the problems you find).
- **Gold**: a **star schema** answering at least:
  - net revenue and cash collected per store and day, **in USD and local currency**
  - number of orders, average basket, delivery time
  - customers (a person with two accounts counts once; test accounts excluded)
  - stockouts per store, category and supplier
  - the product price history (**SCD type 2**)
- **Tests**: generic tests on keys and relationships, **at least two custom tests**,
  at least one **reconciliation** test (two ways of computing the same number must
  agree), and **source freshness**.
- Descriptions for every gold model.

### 2.5 Airflow
- One DAG that runs **every night** and processes the day that just ended:
  load the three sources, then build silver and gold.
- Dependencies between tasks, **retries**, a **sensor** for the supplier files,
  an **alert** when a task fails for good, and **backfill** (re-running past days).
- No business logic in the DAG file: the DAG orchestrates, your Python modules work.

### 2.6 SQL tuning
See `sql_tuning/README.md`: Finance's weekly report takes minutes on the production
database. Make it fast and prove the results are identical.

---

## 3. Every day: operations

From your initial load onward, the company keeps producing data. **Your pipeline must
keep up every night until the end of the project.** Every morning, check that last
night's run succeeded and that the numbers make sense.

**The company will change things without warning**, as real companies do: systems
evolve, partners change their habits, bugs happen, services go down. When something
breaks (or worse, silently produces wrong numbers):

1. detect it (tests and alerts are your eyes),
2. understand the root cause,
3. fix it in your platform (never by changing the company's systems),
4. repair the affected days,
5. write it down: what happened, impact, what you changed.

For any incident where data was late or wrong, write a short **postmortem** with
`docs/POSTMORTEM_TEMPLATE.md`.

---

## 4. Timeline

| Week | Goal | Checkpoint |
|---|---|---|
| Before day 1 | Start the company (first start: ~25 min) | `status` shows today's orders |
| Week 1: 13-19 Oct | Warehouse, loaders (initial + daily), silver | Daily loads into bronze work; silver models tested |
| Week 2: 20-26 Oct | Gold, Airflow, tests, SQL tuning, documentation | The nightly DAG runs on its own; final demo |

## 5. Deliverables

A GitHub repository with:
- your full platform (compose file, loaders, dbt project, DAG)
- `README.md`: how to run it from zero, and an architecture diagram
- `sql_tuning/` deliverables (see its README)
- `docs/`: one short note per change you had to handle, and your postmortem(s)

**Final demo (15 minutes):** architecture in 2 minutes; last night's run; the gold
answers to the business questions; one incident you handled, from detection to fix;
questions on your design choices.

## 6. Grading

| Area | Weight |
|---|---|
| Docker & setup (one command, clean configuration) | 10% |
| Extract & load (incremental, idempotent, robust) | 15% |
| dbt silver (cleaning, tests) | 15% |
| dbt gold (star schema, business answers, tests) | 15% |
| Airflow (daily automation, retries, alerts, backfill) | 15% |
| SQL tuning | 15% |
| Handling the company's changes + postmortem | 15% |

## 7. Rules

- Free tools only.
- Do not modify the company's services (`source-db`, `simulator`, `fx-api`) or their
  settings in `.env`: everybody must have exactly the same company.
- AI assistants are allowed as tools, but you must be able to explain every line you
  submit: the demo questions will check.
