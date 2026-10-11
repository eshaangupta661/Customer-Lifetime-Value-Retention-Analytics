-- SQL Query for Customer CLV Analytics Pipeline


CREATE TABLE online_retail (
    RowID INT IDENTITY(1,1) PRIMARY KEY,
    Invoice nvarchar(50) NOT NULL,
    StockCode nvarchar(50) NOT NULL,
    Description nvarchar(255) NULL,
    Quantity int NOT NULL,
    InvoiceDate datetime2 NULL,
    Price decimal(10,2) NOT NULL,
    Customer_ID int NULL,
    Country nvarchar(50) NOT NULL
);


INSERT INTO online_retail
(Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer_ID, Country)

SELECT Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer_ID, Country
FROM online_retail_1

UNION ALL

SELECT Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer_ID, Country
FROM online_retail_2;



SELECT COUNT(*) 
FROM online_retail;



-- Dim_Customers creation

CREATE TABLE Dim_Customers (
    CustomerKey INT IDENTITY(1,1) PRIMARY KEY,
    Customer_ID INT,
    Country nvarchar(50)
);


-- One row per customer (country = most recent one seen). One row per
-- (Customer_ID, Country) would duplicate fact rows on the join below.
INSERT INTO Dim_Customers (Customer_ID, Country)

SELECT Customer_ID, Country
FROM (
    SELECT
        Customer_ID,
        Country,
        ROW_NUMBER() OVER (PARTITION BY Customer_ID ORDER BY InvoiceDate DESC) AS rn
    FROM (
        SELECT Customer_ID, Country, InvoiceDate FROM online_retail_1
        UNION ALL
        SELECT Customer_ID, Country, InvoiceDate FROM online_retail_2
    ) u
    WHERE Customer_ID IS NOT NULL
) t
WHERE rn = 1;



-- Creation Dim_Products

CREATE TABLE Dim_Products (
    ProductKey INT IDENTITY(1,1) PRIMARY KEY,
    StockCode nvarchar(50),
    Description nvarchar(255)
);

INSERT INTO Dim_Products (StockCode, Description)

-- One row per StockCode: a code can appear with several descriptions, which
-- would otherwise duplicate fact rows on the join below.
SELECT StockCode, MAX(Description)
FROM (
    SELECT StockCode, Description FROM online_retail_1
    UNION ALL
    SELECT StockCode, Description FROM online_retail_2
) t
GROUP BY StockCode;

-- Creation Dim_Country

CREATE TABLE Dim_Country (
    CountryKey INT IDENTITY(1,1) PRIMARY KEY,
    Country nvarchar(50)
);

INSERT INTO Dim_Country (Country)

SELECT DISTINCT Country
FROM (
    SELECT Country FROM online_retail_1
    UNION ALL
    SELECT Country FROM online_retail_2
) t;

-- Creation of Dim_Time

CREATE TABLE Dim_Time (
    TimeKey INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceDate datetime2,
    Year INT,
    Month INT,
    Day INT
);

INSERT INTO Dim_Time (InvoiceDate, Year, Month, Day)

SELECT DISTINCT
    InvoiceDate,
    YEAR(InvoiceDate),
    MONTH(InvoiceDate),
    DAY(InvoiceDate)

FROM (
    SELECT InvoiceDate FROM online_retail_1
    UNION ALL
    SELECT InvoiceDate FROM online_retail_2
) t;


-- Creation of Fact Table

CREATE TABLE Fact_Transactions (
    TransactionKey INT IDENTITY(1,1) PRIMARY KEY,
    CustomerKey INT,
    ProductKey INT,
    TimeKey INT,
    CountryKey INT,
    Quantity INT,
    Price DECIMAL(10,2),

    FOREIGN KEY (CustomerKey) REFERENCES Dim_Customers(CustomerKey),
    FOREIGN KEY (ProductKey) REFERENCES Dim_Products(ProductKey),
    FOREIGN KEY (TimeKey) REFERENCES Dim_Time(TimeKey),
    FOREIGN KEY (CountryKey) REFERENCES Dim_Country(CountryKey)
);


INSERT INTO Fact_Transactions
(CustomerKey, ProductKey, TimeKey, CountryKey, Quantity, Price)

SELECT
    c.CustomerKey,
    p.ProductKey,
    t.TimeKey,
    co.CountryKey,
    r.Quantity,
    r.Price

FROM
(
    SELECT * FROM online_retail_1
    UNION ALL
    SELECT * FROM online_retail_2
) r

JOIN Dim_Customers c
    ON r.Customer_ID = c.Customer_ID

JOIN Dim_Products p
    ON r.StockCode = p.StockCode

JOIN Dim_Time t
    ON r.InvoiceDate = t.InvoiceDate

JOIN Dim_Country co
    ON r.Country = co.Country;
