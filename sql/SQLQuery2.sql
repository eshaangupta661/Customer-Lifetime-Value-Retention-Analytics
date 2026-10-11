-- CTE (Customer Revenue)


WITH CustomerRevenue AS
(
    SELECT
        c.Customer_ID,
        SUM(f.Quantity * f.Price) AS TotalRevenue
    FROM Fact_Transactions f
    JOIN Dim_Customers c
        ON f.CustomerKey = c.CustomerKey
    GROUP BY c.Customer_ID
)

SELECT *
FROM CustomerRevenue
ORDER BY TotalRevenue DESC;


-- Window Function (Running Total of Sales)

SELECT
    t.InvoiceDate,
    SUM(f.Quantity * f.Price) AS DailyRevenue,

    SUM(SUM(f.Quantity * f.Price)) 
        OVER (ORDER BY t.InvoiceDate) AS RunningRevenue

FROM Fact_Transactions f
JOIN Dim_Time t
    ON f.TimeKey = t.TimeKey

GROUP BY t.InvoiceDate
ORDER BY t.InvoiceDate;

-- Rank and Over (Top Customers)

SELECT
    c.Customer_ID,
    SUM(f.Quantity * f.Price) AS TotalRevenue,

    RANK() OVER (
        ORDER BY SUM(f.Quantity * f.Price) DESC
    ) AS CustomerRank

FROM Fact_Transactions f
JOIN Dim_Customers c
    ON f.CustomerKey = c.CustomerKey

GROUP BY c.Customer_ID
ORDER BY CustomerRank;

-- LAG (Compare Sales With Previous Day)

SELECT
    t.InvoiceDate,
    SUM(f.Quantity * f.Price) AS DailyRevenue,

    LAG(SUM(f.Quantity * f.Price))
        OVER (ORDER BY t.InvoiceDate) AS PreviousDayRevenue

FROM Fact_Transactions f
JOIN Dim_Time t
    ON f.TimeKey = t.TimeKey

GROUP BY t.InvoiceDate
ORDER BY t.InvoiceDate;

-- Rolling Average (7-Day Sales Trend)

SELECT
    t.InvoiceDate,
    SUM(f.Quantity * f.Price) AS DailyRevenue,

    AVG(SUM(f.Quantity * f.Price)) 
        OVER (
            ORDER BY t.InvoiceDate
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS Rolling7DayAverage

FROM Fact_Transactions f
JOIN Dim_Time t
    ON f.TimeKey = t.TimeKey

GROUP BY t.InvoiceDate
ORDER BY t.InvoiceDate;


-- Cohort Retention (share of each first-purchase-month cohort active N months later)

WITH Purchases AS
(
    SELECT DISTINCT
        f.CustomerKey,
        DATEFROMPARTS(t.Year, t.Month, 1) AS ActiveMonth
    FROM Fact_Transactions f
    JOIN Dim_Time t ON f.TimeKey = t.TimeKey
    WHERE f.Quantity > 0
),

Cohorts AS
(
    SELECT
        CustomerKey,
        ActiveMonth,
        MIN(ActiveMonth) OVER (PARTITION BY CustomerKey) AS CohortMonth
    FROM Purchases
),

CohortActivity AS
(
    SELECT
        CohortMonth,
        DATEDIFF(MONTH, CohortMonth, ActiveMonth) AS MonthsSinceFirst,
        COUNT(DISTINCT CustomerKey) AS ActiveCustomers
    FROM Cohorts
    GROUP BY CohortMonth, DATEDIFF(MONTH, CohortMonth, ActiveMonth)
)

SELECT
    CohortMonth,
    MonthsSinceFirst,
    ActiveCustomers,
    CAST(ActiveCustomers AS FLOAT)
        / FIRST_VALUE(ActiveCustomers) OVER (
            PARTITION BY CohortMonth ORDER BY MonthsSinceFirst
          ) AS RetentionRate
FROM CohortActivity
ORDER BY CohortMonth, MonthsSinceFirst;


-- RFM Segmentation (Recency, Frequency, Monetary)
-- Scores run 1-5 with 5 = best. Recency is measured against the latest date in the data.

WITH RFM_Base AS
(
    SELECT
        c.Customer_ID,
        MAX(t.InvoiceDate) AS LastPurchaseDate,
        COUNT(DISTINCT t.InvoiceDate) AS Frequency,
        SUM(f.Quantity * f.Price) AS Monetary
    FROM Fact_Transactions f
    JOIN Dim_Customers c ON f.CustomerKey = c.CustomerKey
    JOIN Dim_Time t ON f.TimeKey = t.TimeKey
    WHERE f.Quantity > 0
    GROUP BY c.Customer_ID
),

RFM_Scored AS
(
    SELECT
        Customer_ID,
        DATEDIFF(DAY, LastPurchaseDate, (SELECT MAX(InvoiceDate) FROM Dim_Time)) AS RecencyDays,
        Frequency,
        Monetary,
        NTILE(5) OVER (ORDER BY LastPurchaseDate ASC) AS RecencyScore,
        NTILE(5) OVER (ORDER BY Frequency ASC) AS FrequencyScore,
        NTILE(5) OVER (ORDER BY Monetary ASC) AS MonetaryScore
    FROM RFM_Base
)

SELECT
    *,
    CASE
        WHEN RecencyScore >= 4 AND FrequencyScore >= 4 AND MonetaryScore >= 4 THEN 'Champions'
        WHEN RecencyScore >= 3 AND FrequencyScore >= 3 THEN 'Loyal'
        WHEN RecencyScore >= 4 AND FrequencyScore <= 2 THEN 'New / Promising'
        WHEN RecencyScore <= 2 AND FrequencyScore >= 4 THEN 'At Risk'
        WHEN RecencyScore <= 2 AND FrequencyScore <= 2 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS RFM_Segment
FROM RFM_Scored
ORDER BY Monetary DESC;


-- Customer Segmentation Logic (rule-based, by spend)

WITH CustomerSpend AS
(
    SELECT
        c.Customer_ID,
        SUM(f.Quantity * f.Price) AS Monetary,
        COUNT(*) AS Frequency
    FROM Fact_Transactions f
    JOIN Dim_Customers c
        ON f.CustomerKey = c.CustomerKey
    GROUP BY c.Customer_ID
)

SELECT
    Customer_ID,
    Monetary,
    Frequency,

    CASE
        WHEN Monetary > 10000 THEN 'VIP'
        WHEN Monetary > 5000 THEN 'Loyal'
        WHEN Monetary > 1000 THEN 'Regular'
        ELSE 'Low Value'
    END AS CustomerSegment

FROM CustomerSpend
ORDER BY Monetary DESC;



-- Pareto Analysis — Top Products Driving 80% of Revenue

WITH ProductRevenue AS
(
    SELECT
        p.StockCode,
        p.Description,
        SUM(f.Quantity * f.Price) AS Revenue
    FROM Fact_Transactions f
    JOIN Dim_Products p
        ON f.ProductKey = p.ProductKey
    WHERE f.Quantity > 0
    GROUP BY p.StockCode, p.Description
),

RevenueRank AS
(
    SELECT
        *,
        SUM(Revenue) OVER () AS TotalRevenue,
        SUM(Revenue) OVER (ORDER BY Revenue DESC) AS RunningRevenue
    FROM ProductRevenue
)

SELECT
    StockCode,
    Description,
    Revenue,
    RunningRevenue,
    RunningRevenue / TotalRevenue AS RevenueShare
FROM RevenueRank
ORDER BY Revenue DESC;


-- Customer Lifetime Value (CLV) Ranking

SELECT
    c.Customer_ID,
    co.Country,
    SUM(f.Quantity * f.Price) AS LifetimeValue,

    RANK() OVER (
        ORDER BY SUM(f.Quantity * f.Price) DESC
    ) AS CustomerRank

FROM Fact_Transactions f

JOIN Dim_Customers c
    ON f.CustomerKey = c.CustomerKey

JOIN Dim_Country co
    ON f.CountryKey = co.CountryKey

WHERE f.Quantity > 0

GROUP BY
    c.Customer_ID,
    co.Country

ORDER BY LifetimeValue DESC;


-- Month-to-Month Growth (Revenue Trend)

WITH MonthlyRevenue AS
(
    SELECT
        t.Year,
        t.Month,
        SUM(f.Quantity * f.Price) AS Revenue
    FROM Fact_Transactions f
    JOIN Dim_Time t
        ON f.TimeKey = t.TimeKey
    WHERE f.Quantity > 0
    GROUP BY t.Year, t.Month
)

SELECT
    Year,
    Month,
    Revenue,

    LAG(Revenue) OVER (
        ORDER BY Year, Month
    ) AS PreviousMonthRevenue,

    Revenue - LAG(Revenue) OVER (
        ORDER BY Year, Month
    ) AS RevenueGrowth

FROM MonthlyRevenue
ORDER BY Year, Month;



-- Top Country Markets

SELECT
    co.Country,
    SUM(f.Quantity * f.Price) AS Revenue,
    COUNT(DISTINCT f.CustomerKey) AS Customers
FROM Fact_Transactions f

JOIN Dim_Country co
    ON f.CountryKey = co.CountryKey

WHERE f.Quantity > 0

GROUP BY co.Country
ORDER BY Revenue DESC;


