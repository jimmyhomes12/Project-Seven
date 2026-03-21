-- =============================================================
-- 03_etl_insert_dim_fact.sql
-- Ecommerce Mini Warehouse – ETL: Staging → Dimensions + Facts
-- Run AFTER 01_schema_ddl.sql, 02_staging_tables.sql, and CSV loads
-- =============================================================

-- -------------------------------------------------------------
-- 1. Populate dw.dim_customer from stg_churn
--    (churn data has the richest customer attributes)
-- -------------------------------------------------------------
INSERT INTO dw.dim_customer (
    customer_id,
    region,
    income_band,
    membership_status,
    first_seen_date,
    last_purchase_date,
    is_churned
)
SELECT
    sc.customer_id,
    sc.region,
    sc.income_band,
    sc.membership_status,
    MIN(ss.order_date::DATE)                              AS first_seen_date,
    MAX(ss.order_date::DATE)                              AS last_purchase_date,
    (sc.churn_flag = '1')                                 AS is_churned
FROM stg_churn sc
LEFT JOIN stg_sales ss USING (customer_id)
GROUP BY
    sc.customer_id,
    sc.region,
    sc.income_band,
    sc.membership_status,
    sc.churn_flag
ON CONFLICT (customer_id) DO UPDATE
    SET region             = EXCLUDED.region,
        income_band        = EXCLUDED.income_band,
        membership_status  = EXCLUDED.membership_status,
        last_purchase_date = EXCLUDED.last_purchase_date,
        is_churned         = EXCLUDED.is_churned,
        updated_at         = NOW();

-- Handle customers present in sales but not in churn data
INSERT INTO dw.dim_customer (
    customer_id,
    region,
    income_band,
    membership_status,
    first_seen_date,
    last_purchase_date,
    is_churned
)
SELECT DISTINCT
    ss.customer_id,
    ss.region,
    'Unknown'   AS income_band,
    'Standard'  AS membership_status,
    MIN(ss.order_date::DATE) OVER (PARTITION BY ss.customer_id) AS first_seen_date,
    MAX(ss.order_date::DATE) OVER (PARTITION BY ss.customer_id) AS last_purchase_date,
    FALSE       AS is_churned
FROM stg_sales ss
WHERE ss.customer_id NOT IN (SELECT customer_id FROM dw.dim_customer)
ON CONFLICT (customer_id) DO NOTHING;

-- -------------------------------------------------------------
-- 2. Populate dw.dim_product from stg_sales
-- -------------------------------------------------------------
INSERT INTO dw.dim_product (product_id, category, product_name)
SELECT DISTINCT
    product_id,
    category,
    product_name
FROM stg_sales
ON CONFLICT (product_id) DO NOTHING;

-- -------------------------------------------------------------
-- 3. dw.dim_channel already seeded in 01_schema_ddl.sql
--    Upsert any additional channels found in staging data
-- -------------------------------------------------------------
INSERT INTO dw.dim_channel (channel_name)
SELECT DISTINCT channel
FROM stg_sales
WHERE channel NOT IN (SELECT channel_name FROM dw.dim_channel)
ON CONFLICT (channel_name) DO NOTHING;

-- -------------------------------------------------------------
-- 4. Populate dw.dim_experiment from stg_ab_test
-- -------------------------------------------------------------
INSERT INTO dw.dim_experiment (experiment_name)
SELECT DISTINCT experiment_name
FROM stg_ab_test
ON CONFLICT (experiment_name) DO NOTHING;

-- -------------------------------------------------------------
-- 5. Populate dw.fact_sales
-- -------------------------------------------------------------
INSERT INTO dw.fact_sales (
    customer_id,
    product_id,
    date_key,
    channel_id,
    quantity,
    revenue,
    cogs,
    gross_profit
)
SELECT
    ss.customer_id,
    ss.product_id,
    TO_CHAR(ss.order_date::DATE, 'YYYYMMDD')::INT AS date_key,
    dc.channel_id,
    ss.quantity::INT,
    ss.revenue::NUMERIC,
    NULLIF(ss.cost, '')::NUMERIC                  AS cogs,
    ss.gross_profit::NUMERIC
FROM stg_sales ss
JOIN dw.dim_channel dc ON dc.channel_name = ss.channel;

-- -------------------------------------------------------------
-- 6. Populate dw.fact_churn
-- -------------------------------------------------------------
INSERT INTO dw.fact_churn (
    customer_id,
    churn_flag,
    churn_date,
    total_spend,
    num_orders,
    engagement_score,
    last_order_date
)
SELECT
    customer_id,
    (churn_flag = '1')                                      AS churn_flag,
    NULLIF(churn_date, '')::DATE                            AS churn_date,
    total_spend::NUMERIC,
    num_orders::INT,
    engagement_score::NUMERIC,
    NULLIF(last_order_date, '')::DATE                       AS last_order_date
FROM stg_churn
ON CONFLICT (customer_id) DO UPDATE
    SET churn_flag       = EXCLUDED.churn_flag,
        churn_date       = EXCLUDED.churn_date,
        total_spend      = EXCLUDED.total_spend,
        num_orders       = EXCLUDED.num_orders,
        engagement_score = EXCLUDED.engagement_score,
        last_order_date  = EXCLUDED.last_order_date;

-- -------------------------------------------------------------
-- 7. Populate dw.fact_ab_test
-- -------------------------------------------------------------
INSERT INTO dw.fact_ab_test (
    user_id,
    experiment_id,
    group_name,
    converted,
    date_key,
    revenue
)
SELECT
    sa.user_id,
    de.experiment_id,
    sa.ab_group                                                     AS group_name,
    (sa.converted = '1')                                            AS converted,
    CASE
        WHEN NULLIF(sa.conversion_date, '') IS NOT NULL
        THEN TO_CHAR(sa.conversion_date::DATE, 'YYYYMMDD')::INT
        ELSE NULL
    END                                                             AS date_key,
    COALESCE(NULLIF(sa.revenue, '')::NUMERIC, 0)                   AS revenue
FROM stg_ab_test sa
JOIN dw.dim_experiment de USING (experiment_name)
WHERE sa.user_id IN (SELECT customer_id FROM dw.dim_customer);
