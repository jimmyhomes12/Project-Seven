-- =============================================================
-- 04_quality_checks.sql
-- Ecommerce Mini Warehouse – Data Quality Checks
-- Run after ETL to validate referential integrity and data health
-- =============================================================

-- -------------------------------------------------------------
-- 0. Summary row counts
-- -------------------------------------------------------------
SELECT 'dw.dim_customer'    AS table_name, COUNT(*) AS row_count FROM dw.dim_customer
UNION ALL
SELECT 'dw.dim_product',    COUNT(*) FROM dw.dim_product
UNION ALL
SELECT 'dw.dim_date',       COUNT(*) FROM dw.dim_date
UNION ALL
SELECT 'dw.dim_channel',    COUNT(*) FROM dw.dim_channel
UNION ALL
SELECT 'dw.dim_experiment', COUNT(*) FROM dw.dim_experiment
UNION ALL
SELECT 'dw.fact_sales',     COUNT(*) FROM dw.fact_sales
UNION ALL
SELECT 'dw.fact_churn',     COUNT(*) FROM dw.fact_churn
UNION ALL
SELECT 'dw.fact_ab_test',   COUNT(*) FROM dw.fact_ab_test
ORDER BY table_name;

-- -------------------------------------------------------------
-- 1. Referential integrity: orphaned rows in fact tables
-- -------------------------------------------------------------

-- fact_sales → dim_customer
SELECT 'fact_sales: orphan customer_id' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_sales fs
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_customer dc WHERE dc.customer_id = fs.customer_id
);

-- fact_sales → dim_product
SELECT 'fact_sales: orphan product_id' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_sales fs
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_product dp WHERE dp.product_id = fs.product_id
);

-- fact_sales → dim_date
SELECT 'fact_sales: orphan date_key' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_sales fs
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_date dd WHERE dd.date_key = fs.date_key
);

-- fact_churn → dim_customer
SELECT 'fact_churn: orphan customer_id' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_churn fc
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_customer dc WHERE dc.customer_id = fc.customer_id
);

-- fact_churn → dim_date
SELECT 'fact_churn: orphan date_key' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_churn fc
WHERE fc.date_key IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM dw.dim_date dd WHERE dd.date_key = fc.date_key
);

-- fact_ab_test → dim_customer
SELECT 'fact_ab_test: orphan user_id' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_ab_test fa
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_customer dc WHERE dc.customer_id = fa.user_id
);

-- fact_ab_test → dim_experiment
SELECT 'fact_ab_test: orphan experiment_id' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_ab_test fa
WHERE fa.experiment_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM dw.dim_experiment de WHERE de.experiment_id = fa.experiment_id
);

-- -------------------------------------------------------------
-- 2. NULL checks in key columns
-- -------------------------------------------------------------

SELECT 'dim_customer: NULL region'            AS check_name, COUNT(*) AS issues FROM dw.dim_customer WHERE region IS NULL
UNION ALL
SELECT 'dim_customer: NULL income_band',       COUNT(*) FROM dw.dim_customer WHERE income_band IS NULL
UNION ALL
SELECT 'dim_product: NULL category',           COUNT(*) FROM dw.dim_product WHERE category IS NULL
UNION ALL
SELECT 'fact_sales: NULL revenue',             COUNT(*) FROM dw.fact_sales WHERE revenue IS NULL
UNION ALL
SELECT 'fact_sales: NULL quantity',            COUNT(*) FROM dw.fact_sales WHERE quantity IS NULL
UNION ALL
SELECT 'fact_churn: NULL total_spend',         COUNT(*) FROM dw.fact_churn WHERE total_spend IS NULL
UNION ALL
SELECT 'fact_ab_test: NULL experiment_id',     COUNT(*) FROM dw.fact_ab_test WHERE experiment_id IS NULL;

-- -------------------------------------------------------------
-- 3. Business-rule checks
-- -------------------------------------------------------------

-- Revenue must be non-negative
SELECT 'fact_sales: negative revenue' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_sales
WHERE revenue < 0;

-- Quantity must be positive
SELECT 'fact_sales: zero or negative quantity' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_sales
WHERE quantity <= 0;

-- Churn date should only be set when churn_flag is TRUE
SELECT 'fact_churn: churn_date set but churn_flag=false' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_churn
WHERE churn_flag = FALSE AND churn_date IS NOT NULL;

-- A/B test group must be control or treatment
SELECT 'fact_ab_test: invalid group_name value' AS check_name,
       COUNT(*) AS issues
FROM dw.fact_ab_test
WHERE group_name NOT IN ('control', 'treatment');

-- income_band check
SELECT 'dim_customer: invalid income_band' AS check_name,
       COUNT(*) AS issues
FROM dw.dim_customer
WHERE income_band NOT IN ('Low', 'Medium', 'High', 'Unknown');

-- -------------------------------------------------------------
-- 4. Duplicate checks
-- -------------------------------------------------------------

-- Duplicate customer IDs in dim_customer
SELECT 'dim_customer: duplicate customer_id' AS check_name,
       COUNT(*) AS issues
FROM (
    SELECT customer_id, COUNT(*) AS cnt
    FROM dw.dim_customer
    GROUP BY customer_id
    HAVING COUNT(*) > 1
) dups;

-- Duplicate product IDs in dim_product
SELECT 'dim_product: duplicate product_id' AS check_name,
       COUNT(*) AS issues
FROM (
    SELECT product_id, COUNT(*) AS cnt
    FROM dw.dim_product
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
FROM dw.fact_sales fs
JOIN dw.dim_channel dc USING (channel_id)
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
FROM dw.fact_churn fc
JOIN dw.dim_customer cust USING (customer_id)
GROUP BY cust.region
ORDER BY churn_rate_pct DESC;

-- Conversion rate by A/B experiment and group
SELECT
    de.experiment_name,
    fa.group_name,
    COUNT(*)                                           AS participants,
    SUM(CASE WHEN fa.converted THEN 1 ELSE 0 END)     AS conversions,
    ROUND(
        100.0 * SUM(CASE WHEN fa.converted THEN 1 ELSE 0 END) / COUNT(*),
        2
    )                                                  AS conversion_rate_pct
FROM dw.fact_ab_test fa
JOIN dw.dim_experiment de USING (experiment_id)
GROUP BY de.experiment_name, fa.group_name
ORDER BY de.experiment_name, fa.group_name;
