#!/usr/bin/env bash
# =============================================================
# 02b_load_staging_data.sh
# Ecommerce Mini Warehouse – Load CSVs into staging tables
#
# Usage (run from the Ecommerce_Mini_Warehouse_Postgres/ directory):
#   bash sql/02b_load_staging_data.sh [dbname] [host] [port] [user]
#
# Defaults: dbname=ecommerce_warehouse  host=localhost  port=5432  user=postgres
#
# The \COPY commands below are psql client meta-commands.  They run
# the file-read on the CLIENT side, so relative paths resolve from
# the directory where this script is executed (i.e. the project root
# Ecommerce_Mini_Warehouse_Postgres/).
# =============================================================

DB=${1:-ecommerce_warehouse}
HOST=${2:-localhost}
PORT=${3:-5432}
USER=${4:-postgres}

psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" <<'EOF'
\COPY staging.stg_sales   (order_id, customer_id, product_id, channel, order_date, category, product_name, region, quantity, unit_price, revenue, cost, gross_profit) FROM 'data/sales_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
\COPY staging.stg_churn   (customer_id, region, income_band, membership_status, total_spend, num_orders, last_order_date, days_since_last_order, engagement_score, churn_flag, churn_date) FROM 'data/churn_raw.csv'   WITH (FORMAT CSV, HEADER TRUE);
\COPY staging.stg_ab_test (user_id, experiment_name, ab_group, converted, conversion_date, revenue, page_views, time_on_site_secs) FROM 'data/ab_test_raw.csv' WITH (FORMAT CSV, HEADER TRUE);
EOF
