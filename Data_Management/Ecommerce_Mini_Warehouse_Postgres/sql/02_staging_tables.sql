-- =============================================================
-- 02_staging_tables.sql
-- Ecommerce Mini Warehouse – Staging (Raw Landing) Tables
-- Purpose: load CSV data as-is before transformation
-- =============================================================

-- -------------------------------------------------------------
-- Drop staging tables if they exist (idempotent re-run)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS stg_sales    CASCADE;
DROP TABLE IF EXISTS stg_churn    CASCADE;
DROP TABLE IF EXISTS stg_ab_test  CASCADE;

-- -------------------------------------------------------------
-- Staging: stg_sales  (mirrors sales_raw.csv)
-- -------------------------------------------------------------
CREATE TABLE stg_sales (
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
CREATE TABLE stg_churn (
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
CREATE TABLE stg_ab_test (
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

-- \COPY stg_sales   FROM 'data/sales_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
-- \COPY stg_churn   FROM 'data/churn_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
-- \COPY stg_ab_test FROM 'data/ab_test_raw.csv' WITH (FORMAT CSV, HEADER TRUE);
