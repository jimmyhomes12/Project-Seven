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
   | `fact_churn.date_key`       | `dim_date.date_key`           | date_key       |
   | `fact_churn.churn_date`     | `dim_date.full_date`          | churn_date (inactive — use date_key relationship for filters) |
   | `fact_ab_test.user_id`      | `dim_customer.customer_id`    | user_id        |
   | `fact_ab_test.experiment_id`| `dim_experiment.experiment_id`| experiment_id  |
   | `fact_ab_test.date_key`     | `dim_date.date_key`           | date_key       |

7. Right-click surrogate / technical key columns → **Hide in report view** to keep the field list clean.

---

## 2. Churn Analysis Dashboard

### Page 1: Churn Overview

#### DAX measures

```dax
-- Total distinct customers in the churn fact
Total Customers = DISTINCTCOUNT(fact_churn[customer_id])

-- Customers who churned
Churned Customers =
CALCULATE(
    DISTINCTCOUNT(fact_churn[customer_id]),
    fact_churn[churn_flag] = TRUE()
)

-- Churn Rate
Churn Rate =
DIVIDE([Churned Customers], [Total Customers])

-- Active Customers (customers with at least one sale)
Active Customers =
CALCULATE(
    DISTINCTCOUNT(fact_churn[customer_id]),
    fact_churn[churn_flag] = FALSE()
)

-- Revenue at Risk from churned customers
-- Also referred to as "Churned Revenue" in the dashboard cards
Churned Revenue =
CALCULATE(
    SUM(fact_sales[revenue]),
    FILTER(fact_churn, fact_churn[churn_flag] = TRUE())
)
```

> **Tip:** `churn_flag` is a PostgreSQL `BOOLEAN` column. In DAX use `= TRUE()` / `= FALSE()` (or `= 1` / `= 0`—both work because DAX treats TRUE as 1).

#### Visuals

| Visual | X / Rows | Y / Values | Notes |
|--------|----------|------------|-------|
| Card ×4 | — | Churn Rate, Total Customers, Churned Customers, Churned Revenue | Pin to top of page; keep cards large and simple |
| Bar chart | `dim_customer[membership_status]` | `[Churn Rate]` | Sorted descending; turn on data labels |
| Line chart | `dim_date[month]` | `[Churn Rate]` | Shows monthly trend; sort by numeric month key if needed |
| Treemap | `dim_customer[region]` | `[Churn Rate]` | Colour saturation = churn rate |

#### Slicers

- `dim_customer[region]`
- `dim_customer[membership_status]`
- `dim_date[full_date]` (range slicer)

#### Page 1 formatting

Apply these settings before adding more pages so the dashboard looks polished and is easier to present:

| Element | Setting |
|---------|---------|
| **Churn Rate** card/values | Format as percentage with 1–2 decimal places (Format pane → Display units: Auto, Value decimal places: 1) |
| **Line chart month axis** | If month names sort alphabetically rather than by calendar order, add a **Sort by column** on `dim_date[month_name]` → sort by `dim_date[month]` (the integer column) |
| **Bar chart data labels** | Format pane → Data labels → On; set font size to 10–11 pt |
| **Cards** | Keep font size large (24–32 pt for the value) and remove borders for a clean executive look |

---

### Customer Segment Measures

Use these on Page 2 (Churn Drivers) or wherever segment breakdowns are needed.

```dax
-- Average number of orders per customer
Avg Orders = AVERAGE(fact_churn[num_orders])

-- Average total spend per customer
Avg Spend = AVERAGE(fact_churn[total_spend])

-- Average satisfaction score per customer
Avg Satisfaction = AVERAGE(fact_churn[satisfaction_score])

-- Average engagement score per customer
Avg Engagement = AVERAGE(fact_churn[engagement_score])
```

> **Note:** `fact_churn` does not contain a `tenure_months` column. If you need tenure, derive it in the ETL or add a computed column: `DATEDIFF('month', dim_customer[first_seen_date], TODAY())`.
>
> Drop any of these onto an axis of `dim_customer[membership_status]`, `dim_customer[region]`, or `dim_customer[income_band]` to get a **Churn Rate by Segment** breakdown.

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
-- Total unique users enrolled in tests
Test Users = DISTINCTCOUNT(fact_ab_test[user_id])

-- Total conversions
Conversions =
CALCULATE(
    COUNTROWS(fact_ab_test),
    fact_ab_test[converted] = TRUE()
)

-- Overall conversion rate (conversions ÷ unique users)
Conversion Rate =
DIVIDE([Conversions], [Test Users])

-- Conversion rate for the control group only
Control Conversion Rate =
CALCULATE(
    [Conversion Rate],
    fact_ab_test[group_name] = "control"
)

-- Conversion rate for the treatment group only
Treatment Conversion Rate =
CALCULATE(
    [Conversion Rate],
    fact_ab_test[group_name] = "treatment"
)

-- Absolute lift: treatment minus control
Lift =
VAR control_conv =
    CALCULATE([Conversion Rate], fact_ab_test[group_name] = "control")
VAR treat_conv =
    CALCULATE([Conversion Rate], fact_ab_test[group_name] = "treatment")
RETURN
    treat_conv - control_conv

-- Relative lift as a percentage
Lift % =
DIVIDE([Lift], [Control Conversion Rate])
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

## 6. Build Order

Follow this sequence to avoid broken measure references and missing relationships.

1. **Confirm relationships** in Model view (verify the relationship mappings in Section 1). The active date filter path for `fact_churn` uses `fact_churn[date_key] → dim_date[date_key]`.
2. **Create churn measures first:** `Total Customers`, `Churned Customers`, `Churn Rate`, `Active Customers`, `Churned Revenue`.
3. **Create customer segment measures:** `Avg Orders`, `Avg Spend`, `Avg Satisfaction`, `Avg Engagement`.
4. **Create A/B test measures:** `Test Users`, `Conversions`, `Conversion Rate`, `Control Conversion Rate`, `Treatment Conversion Rate`, `Lift`, `Lift %`.
5. **Build Page 1 (Churn Overview):** KPI cards (Churn Rate, Total Customers, Churned Customers, Churned Revenue), line chart for churn over time, bar/treemap by region or membership status, slicers. Apply formatting (Churn Rate as %, data labels on bar chart, large card values).
6. **Build Page 2 (Churn Drivers):** scatter plot, decomposition tree, key influencers visual.
7. **Build Page 3 (A/B Test Results):** experiment matrix, clustered bar (control vs. treatment), lift card, optional CI line chart.
8. **Publish** to Power BI Service (optional, see Section 4).

---

## Quick-start checklist (≈30 minutes)

- [ ] PostgreSQL is running and `ecommerce_warehouse` is populated (see [README.md](README.md)).
- [ ] Open Power BI Desktop → **Get Data → PostgreSQL database** → `localhost`, `ecommerce_warehouse`.
- [ ] Select the eight `dw.*` tables and click **Load**.
- [ ] In Model view, verify all relationships. Ensure the active date relationship for `fact_churn` uses `fact_churn[date_key] → dim_date[date_key]`; the `churn_date → full_date` relationship can be set to inactive.
- [ ] Create the five core churn DAX measures (`Total Customers`, `Churned Customers`, `Churn Rate`, `Active Customers`, `Churned Revenue`).
- [ ] Create the four customer segment measures (`Avg Orders`, `Avg Spend`, `Avg Satisfaction`, `Avg Engagement`).
- [ ] Create the seven A/B test measures (`Test Users`, `Conversions`, `Conversion Rate`, `Control Conversion Rate`, `Treatment Conversion Rate`, `Lift`, `Lift %`).
- [ ] Add the **Churn Rate** card as a smoke test and confirm it responds to the region/membership_status slicers.
- [ ] Add remaining Page 1 visuals: Total Customers, Churned Customers, Churned Revenue cards; line chart (month vs Churn Rate); bar chart (membership_status or region vs Churn Rate).
- [ ] Apply Page 1 formatting: Churn Rate as percentage (1–2 dp), data labels on bar chart, large card values, month axis sorted by numeric key.
- [ ] Add Page 2 churn-driver visuals.
- [ ] Add the A/B Test Results page with the matrix, lift bar chart, and optional CI line chart.
- [ ] Publish to Power BI Service (optional).
