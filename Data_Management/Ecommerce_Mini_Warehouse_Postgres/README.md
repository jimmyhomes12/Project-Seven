# Ecommerce Mini Warehouse — PostgreSQL

A self-contained, recruiter-ready data warehouse project built on **PostgreSQL**.  
It ingests three raw CSV data sets (retail sales, customer churn, and A/B-test results) into a clean **star-schema** warehouse, then runs automated data-quality checks.

---

## Folder Structure

```
Ecommerce_Mini_Warehouse_Postgres/
├── data/
│   ├── sales_raw.csv         # Retail transaction data
│   ├── churn_raw.csv         # Customer churn attributes & labels
│   └── ab_test_raw.csv       # A/B experiment results
├── sql/
│   ├── 01_schema_ddl.sql          # Create dimension & fact tables
│   ├── 02_staging_tables.sql      # Raw landing (staging) tables + COPY commands
│   ├── 03_etl_insert_dim_fact.sql # Transform staging → warehouse
│   ├── 04_quality_checks.sql      # Referential integrity & business-rule checks
│   └── 05_sample_analytics.sql   # Sample analytical queries
├── notebooks/
│   └── 01_etl_and_quality_checks.ipynb  # End-to-end ETL + QC in Python
├── tests/
│   └── test_warehouse.py     # Automated pytest suite (24 tests)
├── diagrams/
│   └── ecommerce_star_schema.png    # ERD / star-schema diagram
└── README.md
```

---

## Star Schema

![Star Schema](diagrams/ecommerce_star_schema.png)

### Dimension Tables

| Table | Key columns |
|-------|-------------|
| `dim_customer` | `customer_id`, `region`, `income_band`, `membership_status`, `first_seen_date`, `is_churned` |
| `dim_product`  | `product_id`, `category`, `product_name` |
| `dim_date`     | `date_key` (YYYYMMDD int), `full_date`, `year`, `quarter`, `month`, `week`, `day`, `is_weekend` |
| `dim_channel`  | `channel_id`, `channel_name` |

### Fact Tables

| Table | Grain | Key measures |
|-------|-------|-------------|
| `fact_sales`   | One row per transaction | `quantity`, `revenue`, `gross_profit` |
| `fact_churn`   | One row per customer    | `churn_flag`, `total_spend`, `engagement_score` |
| `fact_ab_test` | One row per experiment participant | `converted`, `revenue` |

---

## Quick Start

### 1 — Create & connect to the database

```bash
createdb ecommerce_warehouse
psql -d ecommerce_warehouse
```

### 2 — Run SQL scripts in order

```sql
\i sql/01_schema_ddl.sql
\i sql/02_staging_tables.sql

-- Load CSVs (run from the project root)
\COPY staging.stg_sales   FROM 'data/sales_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
\COPY staging.stg_churn   FROM 'data/churn_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
\COPY staging.stg_ab_test FROM 'data/ab_test_raw.csv' WITH (FORMAT CSV, HEADER TRUE);

\i sql/03_etl_insert_dim_fact.sql
\i sql/04_quality_checks.sql
```

### 3 — Or run everything from the Jupyter notebook

```bash
pip install sqlalchemy psycopg2-binary pandas jupyter

# Set connection env vars (defaults: postgres/postgres on localhost:5432)
export PG_USER=postgres
export PG_PASSWORD=your_password

jupyter notebook notebooks/01_etl_and_quality_checks.ipynb
```

### 4 — Run the automated test suite

```bash
pip install pytest psycopg2-binary sqlalchemy pandas

# Optional: set connection env vars (same defaults as above)
export PG_USER=postgres
export PG_PASSWORD=your_password

# From the Ecommerce_Mini_Warehouse_Postgres/ directory:
pytest tests/test_warehouse.py -v
```

The suite builds a temporary database (`ecommerce_warehouse_test`), runs the
full pipeline, and validates 24 checks covering row counts, referential
integrity, business rules, and aggregate sanity.  It drops the database on
completion.

---

## Data Quality Checks (`04_quality_checks.sql`)

| Category | Checks performed |
|----------|-----------------|
| Row counts | Summary count for every table |
| Referential integrity | Orphan FK rows across all fact tables |
| NULL checks | Critical NOT-NULL columns in dims & facts |
| Business rules | Negative revenue, invalid `income_band`, invalid `ab_group`, mismatched `churn_date` |
| Duplicates | Duplicate PKs in dimension tables |
| Aggregates | Revenue by channel · Churn rate by region · A/B conversion rates |

---

## Sample Analytical Queries

```sql
-- Monthly revenue trend
SELECT dd.year, dd.month, SUM(fs.revenue) AS total_revenue
FROM fact_sales fs
JOIN dim_date dd ON dd.date_key = fs.date_key
GROUP BY dd.year, dd.month
ORDER BY dd.year, dd.month;

-- Churn rate by income band
SELECT dc.income_band,
       COUNT(*) AS customers,
       ROUND(100.0 * SUM(CASE WHEN fc.churn_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_churn fc
JOIN dim_customer dc USING (customer_id)
GROUP BY dc.income_band;

-- A/B test lift (treatment vs control)
SELECT experiment_name,
       ab_group,
       ROUND(100.0 * SUM(converted::INT) / COUNT(*), 2) AS cvr_pct
FROM fact_ab_test
GROUP BY experiment_name, ab_group
ORDER BY experiment_name, ab_group;
```

---

## Requirements

| Tool | Version |
|------|---------|
| PostgreSQL | ≥ 13 |
| Python | ≥ 3.9 |
| pandas | ≥ 1.5 |
| SQLAlchemy | ≥ 2.0 |
| psycopg2-binary | ≥ 2.9 |
| jupyter | any recent |
