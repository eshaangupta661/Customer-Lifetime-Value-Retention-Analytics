# Customer Lifetime Value & Retention Analytics

**SQL Server · T-SQL · Python · scikit-learn · Power BI**

### End-to-End Pipeline: Data Modelling · SQL Analytics (RFM, Cohort Retention) · CLV Prediction · Power BI

**Highlights**
- Full analytical layer written in SQL: CTEs and window functions independently reproduce RFM segmentation, cohort retention and revenue metrics, with reconciliation checks (`SQLQuery3.sql`) proving the dashboard figures tie back exactly to the source transactions.
- Found and fixed a **target-leakage bug** in the CLV model: an early version scored deceptively well because features were computed over the full timeline rather than only the observation window. The pipeline now uses a time-based split (see [Machine Learning](#machine-learning-mainpy)).

---

## Project Overview

This project builds a complete business intelligence solution on top of the **Online Retail II** public dataset - a real-world e-commerce transaction dataset covering UK-based sales from 2009 to 2011. The pipeline takes raw transactional CSV data through every stage of a professional BI workflow: data modelling in SQL Server, advanced analytics with window functions and CTEs, machine learning for Customer Lifetime Value prediction, and interactive dashboarding in Power BI.

---
## Logical Flow

### Step 1 - Structuring the data (SQLQuery1.sql).
I begin with approximately one million raw transaction rows, where each row represents a simple receipt: a customer purchasing a product, in a specific location, at a certain time and price. To make this data usable, I design and implement a star schema. I separate the data into dimension tables such as customers, products, countries, and time, along with a central fact table for transactions. This transformation makes the data efficient to query and logically organized.

### Step 2 - Extracting analytical insights (SQLQuery2.sql).
Once the structure is in place, I perform analytical queries to extract business intelligence. I identify top customers, analyze revenue trends over time, and evaluate short-term sales patterns. I also calculate RFM (Recency, Frequency, Monetary) metrics to understand customer behavior and detect potential churn. This step converts structured data into meaningful insights.

### Step 2b - Validating the numbers (SQLQuery3.sql).
Reconciliation queries compare row counts, total revenue and per-customer revenue between the raw source tables and the star schema, and check that dimension keys are unique so joins can't fan out and inflate revenue. Every check must return `OK`.

### Step 3 - Predicting customer value (main.py).
Using features computed from SQL over an observation window, I build a machine learning model to estimate Customer Lifetime Value (CLV). The model predicts how much each customer is expected to spend in the following 180 days. Based on these predictions, I segment customers into four categories: Low Value, Medium Value, High Value, and VIP. I then store these predictions back into the database for further use.

### Step 4 - Visualizing the results (Retail.pbix).
Finally, I load the data into Power BI to create an interactive dashboard. This allows users to explore revenue by country, analyze product performance, understand customer segments, and view machine learning predictions. All insights are accessible visually, without requiring technical knowledge.

The intellectual progression of my work follows a clear path:
raw data → structured data → analytical insights → predictive modeling → interactive visualization.

## Pipeline Architecture

```
Raw Data (CSV)
    │
    ▼
SQL Server - Star Schema Design
    │  SQLQuery1.sql
    │  • online_retail_1.csv + online_retail_2.csv loaded
    │  • Dimensional model built:
    │    Dim_Customers · Dim_Products · Dim_Country · Dim_Time
    │    Fact_Transactions (with foreign keys)
    │
    ▼
Advanced SQL Analytics
    │  SQLQuery2.sql
    │  • CTEs for customer revenue aggregation
    │  • Window functions: Running totals, RANK(), LAG(), Rolling averages
    │  • Cohort retention by first purchase month
    │  • RFM scoring (Recency, Frequency, Monetary)
    │  • Customer segmentation logic
    │  • Pareto analysis (top products driving 80% of revenue)
    │  • Month-to-month revenue growth
    │
    ▼
Reconciliation Checks
    │  SQLQuery3.sql
    │  • Source vs star schema: rows, revenue, per-customer revenue
    │  • Dimension key uniqueness (no join fan-out)
    │
    ▼
Machine Learning (Python)
    │  main.py
    │  • Time-based split: features from the observation window only,
    │    target = revenue in the following 180 days (no target leakage)
    │  • Feature engineering: RecencyDays, TenureDays
    │  • Random Forest Regressor trained on customer features
    │  • Model evaluation: MAE + R² score on held-out customers
    │  • Predicted CLV generated for all customers
    │  • Customers segmented into 4 tiers via quantile binning:
    │    Low Value · Medium Value · High Value · VIP
    │  • Predictions written back to SQL Server:
    │    ML_Customer_CLV_Predictions table
    │
    ▼
Power BI Dashboard
    Retail.pbix
    • Connected to SQL Server via DirectQuery / Import
    • 4 report pages with interactive visuals
    • DAX measures for business KPIs
    • ML predictions surfaced as CLV segment visuals
```

---

## Dataset

**Source:** [Online Retail II - UCI Machine Learning Repository](https://archive.ics.uci.edu/ml/datasets/Online+Retail+II)

| File | Rows | Period |
|------|------|--------|
| `online_retail_1.csv` | 525,461 | 2009–2010 |
| `online_retail_2.csv` | 541,910 | 2010–2011 |
| **Total** | **1,067,371** | **2009–2011** |

**Columns:** Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer ID, Country

---

## Database Schema - Star Model

```
                    ┌─────────────────┐
                    │  Dim_Customers  │
                    │  CustomerKey PK │
                    │  Customer_ID    │--------------------------------------------
                    │  Country        │                                            │
                    └────────┬────────┘                            
                             │       
┌──────────────┐    ┌────────▼──────────┐    ┌─────────────────┐
│  Dim_Time    │    │  Fact_Transactions│    │  Dim_Products   │                   │
│  TimeKey PK  ├────│  TransactionKey PK│────│  ProductKey PK  │
│  InvoiceDate │    │  CustomerKey FK   │    │  StockCode      │
│  Year        │    │  ProductKey FK    │    │  Description    │
│  Month       │    │  TimeKey FK       │    └─────────────────┘                   │
│  Day         │    │  CountryKey FK    │
└──────────────┘    │  Quantity         │    ┌─────────────────┐
                    │  Price            │    │  Dim_Country    │                   │
                    └────────┬──────────┘    │  CountryKey PK  │
                             └──────────────►│  Country        
                                             └─────────────────┘
                                                                                   │
                                                                                    
                    ┌──────────────────────────────┐
                    │  ML_Customer_CLV_Predictions  │------------------------------│
                    │  Customer_ID                  │
                    │  Predicted_CLV                │
                    │  CLV_Segment                  │
                    └──────────────────────────────┘
```

---

## SQL Analytics (SQLQuery2.sql)

Advanced queries demonstrating professional SQL patterns:

| Query | Technique | Purpose |
|-------|-----------|---------|
| Customer Revenue | CTE | Aggregate total spend per customer |
| Running Total | Window - SUM OVER ORDER BY | Cumulative revenue over time |
| Top Customers | Window - RANK() OVER | Customer revenue ranking |
| Day-over-Day | Window - LAG() | Compare sales with previous day |
| 7-Day Rolling Avg | Window - ROWS BETWEEN | Smooth daily revenue trend |
| Cohort Retention | CTEs + MIN() OVER, FIRST_VALUE() | % of each first-purchase-month cohort active N months later |
| RFM Segmentation | Window - NTILE(5) + CASE WHEN | Recency, Frequency, Monetary scores and segments |
| Customer Segmentation | CASE WHEN | Rule-based spend segments |
| Pareto Analysis | Window - Running SUM | Top products driving 80% of revenue |
| CLV Ranking | Window - RANK() | Lifetime value by customer-country |
| MoM Growth | CTE + LAG() | Month-over-month revenue change |
| Top Country Markets | GROUP BY | Revenue and customer count by country |

---

## SQL Validation (SQLQuery3.sql)

Reconciliation queries that must all return `Status = 'OK'`:

| Check | What it proves |
|-------|----------------|
| Row count, source vs fact | No rows lost or duplicated in the star-schema load |
| Total revenue, source vs fact | Dashboard totals tie to source transactions |
| Per-customer revenue | No offsetting errors hidden inside the grand total |
| Unique `Customer_ID` / `StockCode` in dimensions | Joins can't fan out and inflate revenue |
| Monthly revenue sums to fact total | Time-based analytics are complete |

---

## Machine Learning (main.py)

**Model:** Random Forest Regressor (`sklearn`)

### Avoiding target leakage
An early version of the model computed features over the full timeline and used the customer's total revenue as the prediction target, so the answer was effectively contained in the inputs and the model scored deceptively well. The discrepancy was traced to its cause and the pipeline was rebuilt on a **time-based split**:

- **Observation window:** everything up to `cutoff = last transaction date − 180 days`. All features are computed from this window only.
- **Prediction window:** the 180 days after the cutoff. The target is the revenue each customer generates in this window (0 if they did not purchase).
- Final scoring recomputes features as of the latest date and predicts the *next* 180 days.

**Features used (observation window only):**
| Feature | Description |
|---------|-------------|
| PurchaseFrequency | Number of distinct purchase dates per customer |
| TotalRevenue | Historical spend up to the cutoff |
| AvgOrderValue | Average line value |
| UniqueProducts | Distinct products purchased |
| CountriesPurchased | Number of countries transacted in |
| RecencyDays | Days from last purchase to the cutoff |
| TenureDays | Days from first purchase to the cutoff |

**Target variable:** `FutureRevenue` - revenue in the 180 days after the cutoff

**Pipeline steps:**
1. Extract customer features via SQL from the star schema, as of the cutoff date
2. Extract the target (future revenue) from the prediction window
3. Train/test split on customers (80/20, random_state=42)
4. Train Random Forest (200 estimators, max_depth=10)
5. Evaluate with MAE and R² score on held-out customers
6. Re-compute features as of the latest date and predict each customer's next-180-day value
7. Segment customers into 4 CLV tiers using `pd.qcut`:
   - **Low Value** - bottom 25%
   - **Medium Value** - 25–50th percentile
   - **High Value** - 50–75th percentile
   - **VIP** - top 25%
8. Export predictions to SQL Server (`ML_Customer_CLV_Predictions`)

---

## Power BI Dashboard (Retail.pbix)

**4 report pages:**

| Page | Focus | Key Visuals |
|------|-------|-------------|
| Page 1 | Sales Overview | KPI cards, revenue by country, trend line, map, donut |
| Page 2 | Product Performance | Top products bar, treemap, KPI visual |
| Page 3 | Customer Analysis | Customer table, bar chart, customer segment shape |
| Page 4 | CLV Predictions | Segment donut, CLV bar chart |


**DAX Measures created:**
- `Total Revenue` · `Total Orders` · `Avg Order Value`
- `Purchase Frequency` · `Unique Products` · `Unique Customers`
- `Revenue MoM Change %` · `Running Total Revenue`
- `Top Country By Revenue` · `Customer With Highest Revenue`
- `High Value Customers` · `Avg Predicted CLV` · `CLV Segment Distribution %`

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Data Storage | Microsoft SQL Server |
| Data Modelling | T-SQL - Star Schema |
| Advanced Analytics | T-SQL - CTEs, Window Functions |
| Machine Learning | Python - pandas, scikit-learn, matplotlib, seaborn |
| ORM / DB Connection | SQLAlchemy + pyodbc |
| Visualisation | Microsoft Power BI Desktop |

---

## Project Structure

```
retail-intelligence-dashboard/
│
│
├── sql/
│   ├── SQLQuery1.sql             # Schema creation + star model build
│   ├── SQLQuery2.sql             # Advanced analytics queries
│   └── SQLQuery3.sql             # Reconciliation checks
│
├── ml/
│   └── main.py                   # CLV prediction pipeline
│
├── dashboard/
│   └── Retail.pbix               # Power BI report
│   └── screenshots of the pages
└── README.md
```

---

## How to Run

### Prerequisites
- Microsoft SQL Server (any edition) with ODBC Driver 17
- Python 3.9+
- Power BI Desktop (free)

### Step 1 - Load raw data into SQL Server
```sql
-- In SQL Server Management Studio:
-- 1. Create database: Ecommerce_Intelligence_DB
-- 2. Import online_retail_1.csv and online_retail_2.csv
--    using the Import Flat File wizard (right-click database → Tasks → Import Flat File)
-- 3. Run SQLQuery1.sql to build the star schema
```

### Step 2 - Run advanced analytics and reconciliation
```sql
-- Run SQLQuery2.sql in SSMS to execute all analytical queries
-- Run SQLQuery3.sql and confirm every check returns Status = 'OK'
```

### Step 3 - Install Python dependencies
```bash
pip install pandas sqlalchemy pyodbc scikit-learn matplotlib seaborn
```

### Step 4 - Run the ML pipeline
```bash
# Update the server name in main.py line 7 if needed:
# server = "YOUR_SERVER_NAME"
python main.py
```
This trains the model and writes predictions to `ML_Customer_CLV_Predictions` in SQL Server.

### Step 5 - Open the dashboard
1. Open `Retail.pbix` in Power BI Desktop
2. Go to **Transform Data → Data Source Settings**
3. Update the SQL Server connection to your server name
4. Click **Refresh** - all 4 pages populate with your data

---

## Key Insights the Dashboard Surfaces

- **Revenue concentration** - which countries and products drive the majority of sales
- **Customer segmentation** - behavioural breakdown by purchase type
- **CLV tiers** - ML-predicted lifetime value segmentation (Low / Medium / High / VIP)
- **Temporal patterns** - revenue trends, MoM growth, running totals
- **RFM analysis** - recency, frequency and monetary scoring per customer

---

## Dataset Citation

Chen, D. (2019). Online Retail II. UCI Machine Learning Repository.
Available at: https://archive.ics.uci.edu/ml/datasets/Online+Retail+II

---

## License

MIT - free to use and adapt with attribution.
