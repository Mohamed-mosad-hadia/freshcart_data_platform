-- =============================================================================
-- FreshCart source database: table definitions
-- This file runs automatically the first time the source-db container starts.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS app;

-- Dark stores (small warehouses the orders are delivered from)
CREATE TABLE app.stores (
    store_id      integer PRIMARY KEY,
    store_name    text        NOT NULL,
    city          text        NOT NULL,
    country       text        NOT NULL,
    currency      char(3)     NOT NULL,   -- prices of this store are in this currency
    opened_at     date        NOT NULL,
    created_at    timestamptz NOT NULL,
    updated_at    timestamptz NOT NULL
);

-- People who order in the app
CREATE TABLE app.customers (
    customer_id   integer PRIMARY KEY,
    first_name    text        NOT NULL,
    last_name     text        NOT NULL,
    email         text        NOT NULL,
    phone         text,                   -- optional
    city          text        NOT NULL,
    signup_date   date        NOT NULL,
    created_at    timestamptz NOT NULL,
    updated_at    timestamptz NOT NULL
);

-- Product catalogue (reference price in USD)
CREATE TABLE app.products (
    product_id    integer PRIMARY KEY,
    product_name  text          NOT NULL,
    category      text          NOT NULL,
    unit_price_usd numeric(10,2) NOT NULL,
    is_active     boolean       NOT NULL,
    created_at    timestamptz   NOT NULL,
    updated_at    timestamptz   NOT NULL
);

-- One row per order. Status changes after the order is placed:
-- placed -> delivered / cancelled  (updated_at moves when that happens)
CREATE TABLE app.orders (
    order_id      integer PRIMARY KEY,
    customer_id   integer     NOT NULL,
    store_id      integer     NOT NULL,
    order_status  text        NOT NULL,   -- placed | delivered | cancelled
    placed_at     timestamptz NOT NULL,
    delivered_at  timestamptz,            -- NULL until delivered
    created_at    timestamptz NOT NULL,
    updated_at    timestamptz NOT NULL
);

-- Lines of an order. Prices are in the STORE's currency.
CREATE TABLE app.order_items (
    order_item_id integer PRIMARY KEY,
    order_id      integer       NOT NULL,
    product_id    integer       NOT NULL,
    quantity      integer       NOT NULL,
    unit_price    numeric(10,2) NOT NULL,
    line_amount   numeric(12,2) NOT NULL, -- quantity * unit_price
    created_at    timestamptz   NOT NULL,
    updated_at    timestamptz   NOT NULL
);

-- Payments made for orders (store currency)
CREATE TABLE app.payments (
    payment_id     integer PRIMARY KEY,
    order_id       integer       NOT NULL,
    payment_method text          NOT NULL, -- card | wallet | cash
    payment_status text          NOT NULL, -- paid | refunded
    amount         numeric(12,2) NOT NULL,
    paid_at        timestamptz   NOT NULL,
    created_at     timestamptz   NOT NULL,
    updated_at     timestamptz   NOT NULL
);

-- Note: on purpose there are NO foreign keys and NO extra indexes.
-- (Later, the SQL tuning module is about finding and fixing exactly that.)
