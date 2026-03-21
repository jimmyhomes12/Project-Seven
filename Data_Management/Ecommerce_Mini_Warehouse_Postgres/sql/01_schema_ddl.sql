-- =============================================================
-- 01_schema_ddl.sql
-- Ecommerce Mini Warehouse – Dimension & Fact Table Definitions
-- Database: ecommerce_warehouse
-- =============================================================

-- -------------------------------------------------------------
-- Drop tables in reverse dependency order (idempotent re-run)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS fact_ab_test   CASCADE;
DROP TABLE IF EXISTS fact_churn     CASCADE;
DROP TABLE IF EXISTS fact_sales     CASCADE;
DROP TABLE IF EXISTS dim_channel    CASCADE;
DROP TABLE IF EXISTS dim_date       CASCADE;
DROP TABLE IF EXISTS dim_product    CASCADE;
DROP TABLE IF EXISTS dim_customer   CASCADE;

-- -------------------------------------------------------------
-- Dimension: dim_customer
-- -------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_id        VARCHAR(20)  PRIMARY KEY,
    region             VARCHAR(50)  NOT NULL,
    income_band        VARCHAR(20)  NOT NULL CHECK (income_band IN ('Low','Medium','High','Unknown')),
    membership_status  VARCHAR(20)  NOT NULL CHECK (membership_status IN ('Standard','Premium')),
    first_seen_date    DATE         NOT NULL,
    is_churned         BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- -------------------------------------------------------------
-- Dimension: dim_product
-- -------------------------------------------------------------
CREATE TABLE dim_product (
    product_id    VARCHAR(20)  PRIMARY KEY,
    category      VARCHAR(50)  NOT NULL,
    product_name  VARCHAR(100) NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- -------------------------------------------------------------
-- Dimension: dim_date
-- Covers 2020-01-01 → 2030-12-31 (populated via generate_series)
-- -------------------------------------------------------------
CREATE TABLE dim_date (
    date_key   INT         PRIMARY KEY,   -- YYYYMMDD integer key
    full_date  DATE        NOT NULL UNIQUE,
    year       SMALLINT    NOT NULL,
    quarter    SMALLINT    NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month      SMALLINT    NOT NULL CHECK (month   BETWEEN 1 AND 12),
    month_name VARCHAR(10) NOT NULL,
    week       SMALLINT    NOT NULL,      -- ISO week number
    day        SMALLINT    NOT NULL CHECK (day BETWEEN 1 AND 31),
    day_name   VARCHAR(10) NOT NULL,
    is_weekend BOOLEAN     NOT NULL
);

-- Populate dim_date for 2020-01-01 through 2030-12-31
INSERT INTO dim_date (
    date_key, full_date, year, quarter, month, month_name,
    week, day, day_name, is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT           AS date_key,
    d::DATE                               AS full_date,
    EXTRACT(YEAR    FROM d)::SMALLINT     AS year,
    EXTRACT(QUARTER FROM d)::SMALLINT     AS quarter,
    EXTRACT(MONTH   FROM d)::SMALLINT     AS month,
    TO_CHAR(d, 'Month')                   AS month_name,
    EXTRACT(WEEK    FROM d)::SMALLINT     AS week,
    EXTRACT(DAY     FROM d)::SMALLINT     AS day,
    TO_CHAR(d, 'Day')                     AS day_name,
    EXTRACT(DOW     FROM d) IN (0, 6)     AS is_weekend
FROM GENERATE_SERIES(
    '2020-01-01'::DATE,
    '2030-12-31'::DATE,
    '1 day'::INTERVAL
) AS d;

-- -------------------------------------------------------------
-- Dimension: dim_channel
-- -------------------------------------------------------------
CREATE TABLE dim_channel (
    channel_id    SERIAL       PRIMARY KEY,
    channel_name  VARCHAR(50)  NOT NULL UNIQUE
);

INSERT INTO dim_channel (channel_name) VALUES
    ('online'),
    ('store'),
    ('mobile');

-- -------------------------------------------------------------
-- Fact: fact_sales
-- -------------------------------------------------------------
CREATE TABLE fact_sales (
    sale_id       SERIAL       PRIMARY KEY,
    customer_id   VARCHAR(20)  NOT NULL REFERENCES dim_customer(customer_id),
    product_id    VARCHAR(20)  NOT NULL REFERENCES dim_product(product_id),
    date_key      INT          NOT NULL REFERENCES dim_date(date_key),
    channel_id    INT          NOT NULL REFERENCES dim_channel(channel_id),
    quantity      INT          NOT NULL CHECK (quantity > 0),
    revenue       NUMERIC(12,2) NOT NULL CHECK (revenue >= 0),
    gross_profit  NUMERIC(12,2) NOT NULL
);

-- -------------------------------------------------------------
-- Fact: fact_churn
-- -------------------------------------------------------------
CREATE TABLE fact_churn (
    customer_id       VARCHAR(20)   NOT NULL REFERENCES dim_customer(customer_id),
    churn_flag        BOOLEAN       NOT NULL DEFAULT FALSE,
    churn_date        DATE,
    total_spend       NUMERIC(12,2) NOT NULL CHECK (total_spend >= 0),
    num_orders        INT           NOT NULL DEFAULT 0,
    engagement_score  NUMERIC(5,2),
    last_order_date   DATE,
    PRIMARY KEY (customer_id)
);

-- -------------------------------------------------------------
-- Fact: fact_ab_test
-- -------------------------------------------------------------
CREATE TABLE fact_ab_test (
    ab_test_id        SERIAL        PRIMARY KEY,
    user_id           VARCHAR(20)   NOT NULL REFERENCES dim_customer(customer_id),
    experiment_name   VARCHAR(100)  NOT NULL,
    ab_group          VARCHAR(20)   NOT NULL CHECK (ab_group IN ('control','treatment')),
    converted         BOOLEAN       NOT NULL DEFAULT FALSE,
    date_key          INT           REFERENCES dim_date(date_key),
    revenue           NUMERIC(12,2) DEFAULT 0
);

-- Indexes to support common analytical queries
CREATE INDEX idx_fact_sales_customer  ON fact_sales(customer_id);
CREATE INDEX idx_fact_sales_product   ON fact_sales(product_id);
CREATE INDEX idx_fact_sales_date      ON fact_sales(date_key);
CREATE INDEX idx_fact_sales_channel   ON fact_sales(channel_id);

CREATE INDEX idx_fact_churn_flag      ON fact_churn(churn_flag);

CREATE INDEX idx_fact_ab_experiment   ON fact_ab_test(experiment_name);
CREATE INDEX idx_fact_ab_group        ON fact_ab_test(ab_group);
