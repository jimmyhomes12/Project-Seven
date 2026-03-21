-- =============================================================
-- 05_sample_analytics.sql
-- Ecommerce Mini Warehouse – Sample Analytics Queries
-- Run after ETL (03_etl_insert_dim_fact.sql) to explore the data
-- =============================================================

-- -------------------------------------------------------------
-- 1. Monthly revenue by channel
-- -------------------------------------------------------------
SELECT
    dd.year,
    dd.month,
    TRIM(dd.month_name)         AS month_name,
    dc.channel_name,
    COUNT(fs.sale_id)           AS sales_count,
    SUM(fs.revenue)             AS total_revenue,
    SUM(fs.gross_profit)        AS total_profit,
    ROUND(AVG(fs.revenue), 2)   AS avg_order_value
FROM dw.fact_sales fs
JOIN dw.dim_date    dd ON fs.date_key   = dd.date_key
JOIN dw.dim_channel dc ON fs.channel_id = dc.channel_id
GROUP BY dd.year, dd.month, dd.month_name, dc.channel_name
ORDER BY dd.year, dd.month, dc.channel_name;

-- -------------------------------------------------------------
-- 2. Churn rate by membership status
-- -------------------------------------------------------------
SELECT
    dc.membership_status,
    COUNT(fc.customer_id)                                           AS customer_count,
    ROUND(
        SUM(CASE WHEN fc.churn_flag THEN 1 ELSE 0 END)::NUMERIC
        / COUNT(*),
        4
    )                                                               AS churn_rate,
    ROUND(AVG(fc.total_spend), 2)                                   AS avg_total_spend
FROM dw.fact_churn    fc
JOIN dw.dim_customer  dc ON fc.customer_id = dc.customer_id
GROUP BY dc.membership_status
ORDER BY churn_rate DESC;

-- -------------------------------------------------------------
-- 3. Top 15 products by revenue (with category breakdown)
-- -------------------------------------------------------------
SELECT
    dp.category,
    dp.product_name,
    COUNT(fs.sale_id)    AS sales_count,
    SUM(fs.revenue)      AS total_revenue,
    SUM(fs.gross_profit) AS total_profit
FROM dw.fact_sales   fs
JOIN dw.dim_product  dp ON fs.product_id = dp.product_id
GROUP BY dp.category, dp.product_name
ORDER BY total_revenue DESC
LIMIT 15;

-- -------------------------------------------------------------
-- 4. A/B test conversion results by experiment and group
-- -------------------------------------------------------------
SELECT
    de.experiment_name,
    fat.group_name,
    COUNT(fat.ab_test_id)                                           AS test_users,
    SUM(CASE WHEN fat.converted THEN 1 ELSE 0 END)                 AS converts,
    ROUND(
        SUM(CASE WHEN fat.converted THEN 1 ELSE 0 END)::NUMERIC
        / COUNT(*),
        4
    )                                                               AS conversion_rate
FROM dw.fact_ab_test    fat
JOIN dw.dim_experiment  de ON fat.experiment_id = de.experiment_id
GROUP BY de.experiment_name, fat.group_name
ORDER BY de.experiment_name, fat.group_name;
