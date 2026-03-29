"""
test_warehouse.py
=================
End-to-end validation of the Ecommerce Mini Warehouse.

Runs the full pipeline (schema DDL → staging load → ETL → quality checks)
against a temporary PostgreSQL database and asserts that every quality check
returns zero issues.

Usage
-----
    # From the project root (Ecommerce_Mini_Warehouse_Postgres/):
    pytest tests/test_warehouse.py -v

Prerequisites
-------------
    pip install pytest psycopg2-binary sqlalchemy pandas

    PostgreSQL must be running locally.  The test creates and drops a
    dedicated database (ecommerce_warehouse_test) automatically.

Environment variables (all optional, same defaults as the notebook):
    PG_USER      (default: postgres)
    PG_PASSWORD  (default: postgres)
    PG_HOST      (default: localhost)
    PG_PORT      (default: 5432)
"""

import os
import subprocess
import sys
from pathlib import Path

import pandas as pd
import psycopg2
import pytest
from sqlalchemy import create_engine, text

# ---------------------------------------------------------------------------
# Paths & connection settings
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent   # …/Ecommerce_Mini_Warehouse_Postgres
SQL_DIR  = BASE_DIR / "sql"
DATA_DIR = BASE_DIR / "data"

DB_USER     = os.getenv("PG_USER",     "postgres")
DB_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
DB_HOST     = os.getenv("PG_HOST",     "localhost")
DB_PORT     = os.getenv("PG_PORT",     "5432")
TEST_DB     = "ecommerce_warehouse_test"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _admin_conn():
    """Return a psycopg2 connection to the default 'postgres' database."""
    return psycopg2.connect(
        dbname="postgres",
        user=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
    )


def _make_engine(dbname: str):
    url = (
        f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}"
        f"@{DB_HOST}:{DB_PORT}/{dbname}"
    )
    return create_engine(url, future=True)


def _run_sql_file(filepath: Path, engine) -> None:
    """Execute a SQL file via SQLAlchemy, skipping psql meta-commands."""
    raw = filepath.read_text(encoding="utf-8")
    sql = "\n".join(
        line for line in raw.splitlines()
        if not line.lstrip().startswith("\\")
    )
    with engine.begin() as conn:
        conn.execute(text(sql))


def _query(sql: str, engine) -> pd.DataFrame:
    with engine.connect() as conn:
        return pd.read_sql(text(sql), conn)


# ---------------------------------------------------------------------------
# Session-scoped fixture: build the warehouse once per test run
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def engine():
    # 1. Create a clean test database
    admin = _admin_conn()
    admin.autocommit = True
    cur = admin.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {TEST_DB}")
    cur.execute(f"CREATE DATABASE {TEST_DB}")
    cur.close()
    admin.close()

    eng = _make_engine(TEST_DB)

    # 2. Schema DDL (dimensions + fact tables)
    _run_sql_file(SQL_DIR / "01_schema_ddl.sql", eng)

    # 3. Staging tables (CREATE TABLE only; \COPY lines are skipped)
    _run_sql_file(SQL_DIR / "02_staging_tables.sql", eng)

    # 4. Load CSV files into staging schema via pandas
    csv_map = {
        "sales_raw.csv"  : "stg_sales",
        "churn_raw.csv"  : "stg_churn",
        "ab_test_raw.csv": "stg_ab_test",
    }
    for filename, table in csv_map.items():
        df = pd.read_csv(DATA_DIR / filename, dtype=str).fillna("")
        if "group" in df.columns:
            df = df.rename(columns={"group": "ab_group"})
        df.to_sql(table, eng, schema="staging", if_exists="append", index=False)

    # 5. ETL: staging → dimension + fact tables
    _run_sql_file(SQL_DIR / "03_etl_insert_dim_fact.sql", eng)

    yield eng

    # Teardown: drop the test database
    eng.dispose()
    admin = _admin_conn()
    admin.autocommit = True
    cur = admin.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {TEST_DB}")
    cur.close()
    admin.close()


# ---------------------------------------------------------------------------
# Row-count tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("table,min_rows", [
    ("dw.dim_customer",    1),
    ("dw.dim_product",     1),
    ("dw.dim_date",     4018),   # 2020-01-01 → 2030-12-31
    ("dw.dim_channel",     3),
    ("dw.dim_experiment",  1),
    ("dw.fact_sales",      1),
    ("dw.fact_churn",      1),
    ("dw.fact_ab_test",    1),
])
def test_row_counts(engine, table, min_rows):
    """Every warehouse table must contain at least the expected minimum rows."""
    df = _query(f"SELECT COUNT(*) AS cnt FROM {table}", engine)
    assert df["cnt"].iloc[0] >= min_rows, (
        f"{table} has {df['cnt'].iloc[0]} rows; expected ≥ {min_rows}"
    )


# ---------------------------------------------------------------------------
# Referential-integrity tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("label,sql", [
    (
        "fact_sales → dim_customer",
        "SELECT COUNT(*) AS issues FROM dw.fact_sales fs "
        "WHERE NOT EXISTS (SELECT 1 FROM dw.dim_customer dc WHERE dc.customer_id = fs.customer_id)",
    ),
    (
        "fact_sales → dim_product",
        "SELECT COUNT(*) AS issues FROM dw.fact_sales fs "
        "WHERE NOT EXISTS (SELECT 1 FROM dw.dim_product dp WHERE dp.product_id = fs.product_id)",
    ),
    (
        "fact_sales → dim_date",
        "SELECT COUNT(*) AS issues FROM dw.fact_sales fs "
        "WHERE NOT EXISTS (SELECT 1 FROM dw.dim_date dd WHERE dd.date_key = fs.date_key)",
    ),
    (
        "fact_churn → dim_customer",
        "SELECT COUNT(*) AS issues FROM dw.fact_churn fc "
        "WHERE NOT EXISTS (SELECT 1 FROM dw.dim_customer dc WHERE dc.customer_id = fc.customer_id)",
    ),
    (
        "fact_churn → dim_date",
        "SELECT COUNT(*) AS issues FROM dw.fact_churn fc "
        "WHERE fc.date_key IS NOT NULL "
        "AND NOT EXISTS (SELECT 1 FROM dw.dim_date dd WHERE dd.date_key = fc.date_key)",
    ),
    (
        "fact_ab_test → dim_customer",
        "SELECT COUNT(*) AS issues FROM dw.fact_ab_test fa "
        "WHERE NOT EXISTS (SELECT 1 FROM dw.dim_customer dc WHERE dc.customer_id = fa.user_id)",
    ),
    (
        "fact_ab_test → dim_experiment",
        "SELECT COUNT(*) AS issues FROM dw.fact_ab_test fa "
        "WHERE fa.experiment_id IS NOT NULL "
        "AND NOT EXISTS (SELECT 1 FROM dw.dim_experiment de WHERE de.experiment_id = fa.experiment_id)",
    ),
])
def test_referential_integrity(engine, label, sql):
    """No orphaned foreign-key rows in any fact table."""
    df = _query(sql, engine)
    issues = int(df["issues"].iloc[0])
    assert issues == 0, f"Referential integrity violation — {label}: {issues} orphan rows"


# ---------------------------------------------------------------------------
# Business-rule tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("label,sql", [
    (
        "fact_sales: negative revenue",
        "SELECT COUNT(*) AS issues FROM dw.fact_sales WHERE revenue < 0",
    ),
    (
        "fact_sales: zero/negative quantity",
        "SELECT COUNT(*) AS issues FROM dw.fact_sales WHERE quantity <= 0",
    ),
    (
        "fact_churn: churn_date set but churn_flag=false",
        "SELECT COUNT(*) AS issues FROM dw.fact_churn "
        "WHERE churn_flag = FALSE AND churn_date IS NOT NULL",
    ),
    (
        "fact_ab_test: invalid group_name",
        "SELECT COUNT(*) AS issues FROM dw.fact_ab_test "
        "WHERE group_name NOT IN ('control','treatment')",
    ),
    (
        "dim_customer: invalid income_band",
        "SELECT COUNT(*) AS issues FROM dw.dim_customer "
        "WHERE income_band NOT IN ('Low','Medium','High','Unknown')",
    ),
    (
        "dim_customer: duplicate customer_id",
        "SELECT COUNT(*) AS issues FROM ("
        "  SELECT customer_id FROM dw.dim_customer GROUP BY customer_id HAVING COUNT(*) > 1"
        ") dups",
    ),
    (
        "dim_product: duplicate product_id",
        "SELECT COUNT(*) AS issues FROM ("
        "  SELECT product_id FROM dw.dim_product GROUP BY product_id HAVING COUNT(*) > 1"
        ") dups",
    ),
])
def test_business_rules(engine, label, sql):
    """All business-rule checks must report zero issues."""
    df = _query(sql, engine)
    issues = int(df["issues"].iloc[0])
    assert issues == 0, f"Business-rule violation — {label}: {issues} bad rows"


# ---------------------------------------------------------------------------
# Aggregate / sanity tests
# ---------------------------------------------------------------------------

def test_fact_sales_total_revenue_positive(engine):
    """Total revenue across all sales must be greater than zero."""
    df = _query("SELECT SUM(revenue) AS total FROM dw.fact_sales", engine)
    assert float(df["total"].iloc[0]) > 0


def test_ab_test_groups_present(engine):
    """Both 'control' and 'treatment' groups must appear in fact_ab_test."""
    df = _query(
        "SELECT DISTINCT group_name FROM dw.fact_ab_test ORDER BY group_name",
        engine,
    )
    groups = set(df["group_name"].tolist())
    assert "control"   in groups, "Missing 'control' group in fact_ab_test"
    assert "treatment" in groups, "Missing 'treatment' group in fact_ab_test"


def test_churn_flags_not_all_same(engine):
    """fact_churn must contain both churned and non-churned customers."""
    df = _query(
        "SELECT COUNT(*) FILTER (WHERE churn_flag) AS churned, "
        "       COUNT(*) FILTER (WHERE NOT churn_flag) AS active "
        "FROM dw.fact_churn",
        engine,
    )
    assert int(df["churned"].iloc[0]) > 0,  "No churned customers in fact_churn"
    assert int(df["active"].iloc[0])  > 0,  "No active customers in fact_churn"
