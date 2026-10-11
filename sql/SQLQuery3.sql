-- Reconciliation checks
-- Every check should return Status = 'OK' (Difference = 0). Run after SQLQuery1.sql.
-- These validate that the star schema, and therefore the SQL analytics and the
-- Power BI dashboard built on it, reconcile exactly against the source transactions.

WITH Source AS
(
    SELECT Quantity, Price, Customer_ID, StockCode, InvoiceDate, Country
    FROM online_retail_1
    UNION ALL
    SELECT Quantity, Price, Customer_ID, StockCode, InvoiceDate, Country
    FROM online_retail_2
),

SourceTotals AS
(
    SELECT
        COUNT(*) AS RowCnt,
        SUM(CAST(Quantity AS DECIMAL(18,2)) * Price) AS Revenue
    FROM Source
    WHERE Customer_ID IS NOT NULL         -- fact table only holds identified customers
),

FactTotals AS
(
    SELECT
        COUNT(*) AS RowCnt,
        SUM(CAST(Quantity AS DECIMAL(18,2)) * Price) AS Revenue
    FROM Fact_Transactions
)

SELECT
    'Row count: source vs fact' AS CheckName,
    s.RowCnt AS SourceValue,
    f.RowCnt AS ModelValue,
    s.RowCnt - f.RowCnt AS Difference,
    CASE WHEN s.RowCnt = f.RowCnt THEN 'OK' ELSE 'MISMATCH' END AS Status
FROM SourceTotals s CROSS JOIN FactTotals f

UNION ALL

SELECT
    'Total revenue: source vs fact',
    s.Revenue,
    f.Revenue,
    s.Revenue - f.Revenue,
    CASE WHEN s.Revenue = f.Revenue THEN 'OK' ELSE 'MISMATCH' END
FROM SourceTotals s CROSS JOIN FactTotals f

UNION ALL

-- Customer-level revenue must also match (catches offsetting errors)
SELECT
    'Customers with revenue mismatch',
    0,
    COUNT(*),
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'MISMATCH' END
FROM
(
    SELECT Customer_ID, SUM(CAST(Quantity AS DECIMAL(18,2)) * Price) AS Revenue
    FROM Source WHERE Customer_ID IS NOT NULL
    GROUP BY Customer_ID
) s
FULL JOIN
(
    SELECT c.Customer_ID, SUM(CAST(f.Quantity AS DECIMAL(18,2)) * f.Price) AS Revenue
    FROM Fact_Transactions f
    JOIN Dim_Customers c ON f.CustomerKey = c.CustomerKey
    GROUP BY c.Customer_ID
) m ON s.Customer_ID = m.Customer_ID
WHERE ISNULL(s.Revenue, 0) <> ISNULL(m.Revenue, 0)

UNION ALL

-- Dimension keys must be unique, otherwise joins fan out and inflate revenue
SELECT 'Duplicate Customer_ID in Dim_Customers', 0, COUNT(*), COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'MISMATCH' END
FROM (SELECT Customer_ID FROM Dim_Customers GROUP BY Customer_ID HAVING COUNT(*) > 1) d

UNION ALL

SELECT 'Duplicate StockCode in Dim_Products', 0, COUNT(*), COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'MISMATCH' END
FROM (SELECT StockCode FROM Dim_Products GROUP BY StockCode HAVING COUNT(*) > 1) d

UNION ALL

-- Monthly revenue (the MoM query in SQLQuery2.sql) sums back to the fact total
SELECT
    'Monthly revenue sums to fact total',
    f.Revenue,
    m.Revenue,
    f.Revenue - m.Revenue,
    CASE WHEN f.Revenue = m.Revenue THEN 'OK' ELSE 'MISMATCH' END
FROM FactTotals f
CROSS JOIN
(
    SELECT SUM(Revenue) AS Revenue
    FROM
    (
        SELECT t.Year, t.Month, SUM(CAST(fx.Quantity AS DECIMAL(18,2)) * fx.Price) AS Revenue
        FROM Fact_Transactions fx
        JOIN Dim_Time t ON fx.TimeKey = t.TimeKey
        GROUP BY t.Year, t.Month
    ) mm
) m;
