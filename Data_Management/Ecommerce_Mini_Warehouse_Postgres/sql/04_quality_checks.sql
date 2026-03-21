-- =============================================================
-- 04_quality_checks.sql
-- Ecommerce Mini Warehouse – Data Quality Checks
-- Run after ETL to validate referential integrity and data health
-- =============================================================

-- -------------------------------------------------------------
-- 0. Summary row counts
-- -------------------------------------------------------------
SELECT 'dim_customer'  AS table_name, COUNT(*) AS row_count FROM dim_customer
UNION ALL
SELECT 'dim_product',   COUNT(*) FROM dim_product
UNION ALL
SELECT 'dim_date',      COUNT(*) FROM dim_date
UNION ALL
SELECT 'dim_channel',   COUNT(*) FROM dim_channel
UNION ALL
SELECT 'fact_sales',    COUNT(*) FROM fact_sales
UNION ALL
SELECT 'fact_churn',    COUNT(*) FROM fact_churn
UNION ALL
SELECT 'fact_ab_test',  COUNT(*) FROM fact_ab_test
ORDER BY table_name;

-- -------------------------------------------------------------
-- 1. Referential integrity: orphaned rows in fact tables
-- -------------------------------------------------------------

-- fact_sales → dim_customer
SELECT 'fact_sales: orphan customer_id' AS check_name,
       COUNT(*) AS issues
FROM fact_sales fs
WHERE NOT EXISTS (
    SELECT 1 FROM dim_customer dc WHERE dc.customer_id = fs.customer_id
);

-- fact_sales → dim_product
SELECT 'fact_sales: orphan product_id' AS check_name,
       COUNT(*) AS issues
FROM fact_sales fs
WHERE NOT EXISTS (
    SELECT 1 FROM dim_product dp WHERE dp.product_id = fs.product_id
);

-- fact_sales → dim_date
SELECT 'fact_sales: orphan date_key' AS check_name,
       COUNT(*) AS issues
FROM fact_sales fs
WHERE NOT EXISTS (
    SELECT 1 FROM dim_date dd WHERE dd.date_key = fs.date_key
);

-- fact_churn → dim_customer
SELECT 'fact_churn: orphan customer_id' AS check_name,
       COUNT(*) AS issues
FROM fact_churn fc
WHERE NOT EXISTS (
    SELECT 1 FROM dim_customer dc WHERE dc.customer_id = fc.customer_id
);

-- fact_ab_test → dim_customer
SELECT 'fact_ab_test: orphan user_id' AS check_name,
       COUNT(*) AS issues
FROM fact_ab_test fa
WHERE NOT EXISTS (
    SELECT 1 FROM dim_customer dc WHERE dc.customer_id = fa.user_id
);

-- -------------------------------------------------------------
-- 2. NULL checks in key columns
-- -------------------------------------------------------------

SELECT 'dim_customer: NULL region'            AS check_name, COUNT(*) AS issues FROM dim_customer WHERE region IS NULL
UNION ALL
SELECT 'dim_customer: NULL income_band',       COUNT(*) FROM dim_customer WHERE income_band IS NULL
UNION ALL
SELECT 'dim_product: NULL category',           COUNT(*) FROM dim_product WHERE category IS NULL
UNION ALL
SELECT 'fact_sales: NULL revenue',             COUNT(*) FROM fact_sales WHERE revenue IS NULL
UNION ALL
SELECT 'fact_sales: NULL quantity',            COUNT(*) FROM fact_sales WHERE quantity IS NULL
UNION ALL
SELECT 'fact_churn: NULL total_spend',         COUNT(*) FROM fact_churn WHERE total_spend IS NULL
UNION ALL
SELECT 'fact_ab_test: NULL experiment_name',   COUNT(*) FROM fact_ab_test WHERE experiment_name IS NULL;

-- -------------------------------------------------------------
-- 3. Business-rule checks
-- -------------------------------------------------------------

-- Revenue must be non-negative
SELECT 'fact_sales: negative revenue' AS check_name,
       COUNT(*) AS issues
FROM fact_sales
WHERE revenue < 0;

-- Quantity must be positive
SELECT 'fact_sales: zero or negative quantity' AS check_name,
       COUNT(*) AS issues
FROM fact_sales
WHERE quantity <= 0;

-- Churn date should only be set when churn_flag is TRUE
SELECT 'fact_churn: churn_date set but churn_flag=false' AS check_name,
       COUNT(*) AS issues
FROM fact_churn
WHERE churn_flag = FALSE AND churn_date IS NOT NULL;

-- A/B test group must be control or treatment
SELECT 'fact_ab_test: invalid ab_group value' AS check_name,
       COUNT(*) AS issues
FROM fact_ab_test
WHERE ab_group NOT IN ('control', 'treatment');

-- income_band check
SELECT 'dim_customer: invalid income_band' AS check_name,
       COUNT(*) AS issues
FROM dim_customer
WHERE income_band NOT IN ('Low', 'Medium', 'High', 'Unknown');

-- -------------------------------------------------------------
-- 4. Duplicate checks
-- -------------------------------------------------------------

-- Duplicate customer IDs in dim_customer
SELECT 'dim_customer: duplicate customer_id' AS check_name,
       COUNT(*) AS issues
FROM (
    SELECT customer_id, COUNT(*) AS cnt
    FROM dim_customer
    GROUP BY customer_id
    HAVING COUNT(*) > 1
) dups;

-- Duplicate product IDs in dim_product
SELECT 'dim_product: duplicate product_id' AS check_name,
       COUNT(*) AS issues
FROM (
    SELECT product_id, COUNT(*) AS cnt
    FROM dim_product
    GROUP BY product_id
    HAVING COUNT(*) > 1
) dups;

-- -------------------------------------------------------------
-- 5. Aggregate sanity checks
-- -------------------------------------------------------------

-- Total revenue per channel
SELECT
    dc.channel_name,
    COUNT(*)                   AS num_sales,
    SUM(fs.revenue)            AS total_revenue,
    ROUND(AVG(fs.revenue), 2)  AS avg_order_revenue
FROM fact_sales fs
JOIN dim_channel dc USING (channel_id)
GROUP BY dc.channel_name
ORDER BY total_revenue DESC;

-- Churn rate by region
SELECT
    cust.region,
    COUNT(*)                                        AS total_customers,
    SUM(CASE WHEN fc.churn_flag THEN 1 ELSE 0 END) AS churned,
    ROUND(
        100.0 * SUM(CASE WHEN fc.churn_flag THEN 1 ELSE 0 END) / COUNT(*),
        2
    )                                               AS churn_rate_pct
FROM fact_churn fc
JOIN dim_customer cust USING (customer_id)
GROUP BY cust.region
ORDER BY churn_rate_pct DESC;

-- Conversion rate by A/B experiment and group
SELECT
    experiment_name,
    ab_group,
    COUNT(*)                                           AS participants,
    SUM(CASE WHEN converted THEN 1 ELSE 0 END)        AS conversions,
    ROUND(
        100.0 * SUM(CASE WHEN converted THEN 1 ELSE 0 END) / COUNT(*),
        2
    )                                                  AS conversion_rate_pct
FROM fact_ab_test
GROUP BY experiment_name, ab_group
ORDER BY experiment_name, ab_group;
