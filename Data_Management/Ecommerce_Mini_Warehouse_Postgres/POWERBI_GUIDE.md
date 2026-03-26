# Power BI Dashboard Guide — Churn & A/B Test Analytics

This guide connects Power BI Desktop to the `ecommerce_warehouse` PostgreSQL database and walks through building a churn analysis dashboard and A/B test results visualisations.

---

## 1. Star Schema Setup in Power BI

### Data model relationships

```
[dim_customer] ←── customer_id ─── [fact_churn]
[dim_date]     ←── full_date  ─── [fact_churn]   (via churn_date)

[dim_channel]  ←── channel_id ─── [fact_sales] ←── product_id ─── [dim_product]
[dim_date]     ←── date_key   ─── [fact_sales]

[dim_experiment] ←── experiment_id ─── [fact_ab_test]
[dim_customer]   ←── customer_id   ─── [fact_ab_test]  (via user_id)
[dim_date]       ←── date_key      ─── [fact_ab_test]
```

> **Note:** `fact_churn` stores `churn_date` as a plain `DATE` column (no integer FK). In the Power BI Model view, create a manual relationship from `fact_churn[churn_date]` → `dim_date[full_date]` instead of relying on auto-detection.

### Steps in Power BI Desktop

1. **Get Data → PostgreSQL database** → enter `localhost` as server and `ecommerce_warehouse` as database.
2. Select these tables (all live in the `dw` schema):
   - `fact_churn`, `fact_sales`, `fact_ab_test`
   - `dim_customer`, `dim_date`, `dim_channel`, `dim_product`, `dim_experiment`
3. Click **Load** (or **Transform Data** if you want to preview first).
4. Open **Model view** → Power BI auto-detects most FK relationships by column name.
5. Manually add the `fact_churn[churn_date]` → `dim_date[full_date]` relationship (right-click a table → **Manage relationships → New**).
6. Verify all relationships:

   | From (many) | To (one) | Join column |
   |-------------|----------|-------------|
   | `fact_sales.customer_id`    | `dim_customer.customer_id`    | customer_id    |
   | `fact_sales.product_id`     | `dim_product.product_id`      | product_id     |
   | `fact_sales.channel_id`     | `dim_channel.channel_id`      | channel_id     |
   | `fact_sales.date_key`       | `dim_date.date_key`           | date_key       |
   | `fact_churn.customer_id`    | `dim_customer.customer_id`    | customer_id    |
   | `fact_churn.churn_date`     | `dim_date.full_date`          | churn_date     |
   | `fact_ab_test.user_id`      | `dim_customer.customer_id`    | user_id        |
   | `fact_ab_test.experiment_id`| `dim_experiment.experiment_id`| experiment_id  |
   | `fact_ab_test.date_key`     | `dim_date.date_key`           | date_key       |

7. Right-click surrogate / technical key columns → **Hide in report view** to keep the field list clean.

---

## 2. Churn Analysis Dashboard

### Page 1: Churn Overview

#### DAX measures

```dax
-- Churn Rate
Churn Rate =
DIVIDE(
    CALCULATE(COUNTROWS(fact_churn), fact_churn[churn_flag] = TRUE()),
    DISTINCTCOUNT(fact_churn[customer_id])
)

-- Active Customers (customers with at least one sale)
Active Customers = DISTINCTCOUNT(fact_sales[customer_id])

-- Total Customers
Total Customers = DISTINCTCOUNT(fact_churn[customer_id])

-- Revenue at Risk from churned customers
Churn Revenue Impact =
CALCULATE(
    SUM(fact_sales[revenue]),
    FILTER(fact_churn, fact_churn[churn_flag] = TRUE())
)
```

> **Tip:** `churn_flag` is a PostgreSQL `BOOLEAN` column. In DAX use `= TRUE()` (or `= 1`—both work because DAX treats TRUE as 1).

#### Visuals

| Visual | X / Rows | Y / Values | Notes |
|--------|----------|------------|-------|
| Card ×4 | — | Churn Rate, Active Customers, Total Customers, Churn Revenue Impact | Pin to top of page |
| Bar chart | `dim_customer[membership_status]` | `[Churn Rate]` | Sorted descending |
| Line chart | `dim_date[month]` | `[Churn Rate]` | Shows monthly trend |
| Treemap | `dim_customer[region]` | `[Churn Rate]` | Colour saturation = churn rate |

#### Slicers

- `dim_customer[region]`
- `dim_customer[membership_status]`
- `dim_date[full_date]` (range slicer)

---

### Page 2: Churn Drivers

#### Visuals

| Visual | Config |
|--------|--------|
| Scatter plot | X-axis: `SUM(fact_churn[total_spend])`, Y-axis: `AVG(fact_churn[satisfaction_score])`, bubble size: `DISTINCTCOUNT(fact_churn[customer_id])`, legend colour: `[Churn Rate]` |
| Decomposition tree | Analyse: `[Churn Rate]`, Explain by: `dim_customer[region]` → `dim_customer[membership_status]` → `dim_customer[income_band]` |
| Key Influencers | Analyse: `[Churn Rate]`, Explain by: membership_status, region, income_band, total_spend, engagement_score |

#### Slicer

- `dim_customer[income_band]` (spending band)

---

## 3. A/B Test Results Visualisations

### DAX measures

```dax
-- Conversion rate per group
Conversion Rate =
DIVIDE(
    CALCULATE(COUNTROWS(fact_ab_test), fact_ab_test[converted] = TRUE()),
    DISTINCTCOUNT(fact_ab_test[ab_test_id])
)

-- Lift: treatment conversion minus control conversion
Lift =
VAR control_conv =
    CALCULATE([Conversion Rate], fact_ab_test[group_name] = "control")
VAR treat_conv =
    CALCULATE([Conversion Rate], fact_ab_test[group_name] = "treatment")
RETURN
    treat_conv - control_conv
```

### Recommended visuals

#### Single-experiment comparison matrix

```
Matrix visual
  Rows:    dim_experiment[experiment_name]
  Columns: fact_ab_test[group_name]
  Values:  [Conversion Rate]
```

#### Conversion lift bar chart

```
Clustered bar chart
  X-axis: dim_experiment[experiment_name]
  Y-axis: [Lift]
  Reference line at 0 (no-effect baseline)
```

#### Conversion trend line chart

```
Line chart
  X-axis: dim_date[full_date]
  Y-axis: [Conversion Rate]
  Legend: fact_ab_test[group_name]
  Filter: single experiment via slicer
```

#### Confidence interval line chart

Add error-bar bounds as separate measures if CI columns are available, or calculate them from the binomial standard error:

```dax
-- Margin of error (95% CI, binomial proportion)
CI Margin =
VAR p = [Conversion Rate]
VAR n = DISTINCTCOUNT(fact_ab_test[ab_test_id])
RETURN
    1.96 * SQRT( DIVIDE(p * (1 - p), n) )

CI Upper = [Conversion Rate] + [CI Margin]
CI Lower = [Conversion Rate] - [CI Margin]
```

---

## 4. Publishing to Power BI Service

### Publish the report

1. **File → Publish → Power BI Service** (sign in with a Microsoft/work account).
2. Choose your workspace and click **Select**.
3. Once published, open the workspace → click the report to confirm it renders.
4. **Share → Embed report → Publish to web** to generate a public iframe snippet for your portfolio.

### Gateway for scheduled refresh (local PostgreSQL)

Because the database runs locally, Power BI Service cannot reach it directly without a gateway:

1. **Power BI Service → Settings → Datasets** → locate your dataset → **Gateway connection**.
2. Download the **On-premises data gateway** from Microsoft and install it on the machine running PostgreSQL.
3. Configure the gateway with your PostgreSQL credentials.
4. Back in Power BI Service, map the dataset to the gateway connection.
5. Set a **Scheduled refresh** (e.g., daily at 06:00).

---

## 5. PostgreSQL Connection Troubleshooting

| Error message | Likely cause | Fix |
|---------------|--------------|-----|
| `PostgreSQL driver not found` | ODBC/Npgsql driver missing | Install the Npgsql driver: [npgsql.org](https://www.npgsql.org/) or run `brew install postgresql-odbc` on macOS |
| `Connection timeout` | PostgreSQL service not running | Start PostgreSQL: `brew services start postgresql` (macOS) or `pg_ctl start` |
| `SSL error` | SSL negotiation mismatch | Append `sslmode=disable` to the connection string, or configure `ssl = on` in `postgresql.conf` |
| `Authentication failed` | Wrong username/password | Verify credentials: `psql -U your_username -d ecommerce_warehouse` |
| `Schema not found` / `relation does not exist` | Missing schema prefix | All warehouse tables are in the `dw` schema. Use **Advanced options** in Power BI's PostgreSQL connector to prefix with `dw.`, or select tables prefixed `dw` in the navigator |

### Verify the connection before loading into Power BI

```bash
psql -h localhost -U your_user -d ecommerce_warehouse -c "\dt dw.*"
```

Expected output: eight tables — `dim_channel`, `dim_customer`, `dim_date`, `dim_experiment`, `dim_product`, `fact_ab_test`, `fact_churn`, `fact_sales`.

---

## Quick-start checklist (≈30 minutes)

- [ ] PostgreSQL is running and `ecommerce_warehouse` is populated (see [README.md](README.md)).
- [ ] Open Power BI Desktop → **Get Data → PostgreSQL database** → `localhost`, `ecommerce_warehouse`.
- [ ] Select the eight `dw.*` tables and click **Load**.
- [ ] In Model view, verify all relationships (add the `churn_date → full_date` relationship manually).
- [ ] Create the four KPI DAX measures (Churn Rate, Active Customers, Total Customers, Churn Revenue Impact).
- [ ] Build the **Churn Rate by Membership Status** bar chart as a smoke test.
- [ ] Add remaining Page 1 visuals and slicers.
- [ ] Add Page 2 churn-driver visuals.
- [ ] Add the A/B Test Results page with the matrix and lift bar chart.
- [ ] Publish to Power BI Service (optional).
