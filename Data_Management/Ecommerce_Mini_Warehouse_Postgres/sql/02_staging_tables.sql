-- =============================================================
-- 02_staging_tables.sql
-- Ecommerce Mini Warehouse – Staging (Raw Landing) Tables
-- Purpose: load CSV data as-is before transformation
-- =============================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- -------------------------------------------------------------
-- Drop staging tables if they exist (idempotent re-run)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS staging.stg_sales    CASCADE;
DROP TABLE IF EXISTS staging.stg_churn    CASCADE;
DROP TABLE IF EXISTS staging.stg_ab_test  CASCADE;

-- -------------------------------------------------------------
-- Staging: stg_sales  (mirrors sales_raw.csv)
-- -------------------------------------------------------------
CREATE TABLE staging.stg_sales (
    order_id      VARCHAR(20),
    customer_id   VARCHAR(20),
    product_id    VARCHAR(20),
    channel       VARCHAR(50),
    order_date    VARCHAR(20),   -- loaded as text; cast during ETL
    category      VARCHAR(50),
    product_name  VARCHAR(100),
    region        VARCHAR(50),
    quantity      VARCHAR(20),
    unit_price    VARCHAR(20),
    revenue       VARCHAR(20),
    cost          VARCHAR(20),
    gross_profit  VARCHAR(20),
    loaded_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -------------------------------------------------------------
-- Staging: stg_churn  (mirrors churn_raw.csv)
-- -------------------------------------------------------------
CREATE TABLE staging.stg_churn (
    customer_id             VARCHAR(20),
    region                  VARCHAR(50),
    income_band             VARCHAR(20),
    membership_status       VARCHAR(20),
    total_spend             VARCHAR(20),
    num_orders              VARCHAR(20),
    last_order_date         VARCHAR(20),
    days_since_last_order   VARCHAR(20),
    engagement_score        VARCHAR(20),
    churn_flag              VARCHAR(10),
    churn_date              VARCHAR(20),
    loaded_at               TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -------------------------------------------------------------
-- Staging: stg_ab_test  (mirrors ab_test_raw.csv)
-- -------------------------------------------------------------
CREATE TABLE staging.stg_ab_test (
    user_id              VARCHAR(20),
    experiment_name      VARCHAR(100),
    ab_group             VARCHAR(20),
    converted            VARCHAR(10),
    conversion_date      VARCHAR(20),
    revenue              VARCHAR(20),
    page_views           VARCHAR(20),
    time_on_site_secs    VARCHAR(20),
    loaded_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Load CSV files into staging tables via COPY
-- Run these COPY commands from psql (adjust file paths as needed)
-- =============================================================

\COPY staging.stg_sales   (order_id, customer_id, product_id, channel, order_date, category, product_name, region, quantity, unit_price, revenue, cost, gross_profit) FROM 'data/sales_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
\COPY staging.stg_churn   (customer_id, region, income_band, membership_status, total_spend, num_orders, last_order_date, days_since_last_order, engagement_score, churn_flag, churn_date) FROM 'data/churn_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
\COPY staging.stg_ab_test (user_id, experiment_name, ab_group, converted, conversion_date, revenue, page_views, time_on_site_secs) FROM 'data/ab_test_raw.csv' WITH (FORMAT CSV, HEADER TRUE);
