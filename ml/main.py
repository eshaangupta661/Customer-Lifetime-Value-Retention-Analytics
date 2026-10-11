import pandas as pd
from sqlalchemy import create_engine, text
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, r2_score
import matplotlib.pyplot as plt
import seaborn as sns


# 1 CONNECT TO SQL SERVER

server = "YOUR_SERVER_NAME"
database = "Ecommerce_Intelligence_DB"

connection_string = (
    f"mssql+pyodbc://@{server}/{database}"
    "?driver=ODBC+Driver+17+for+SQL+Server"
)

engine = create_engine(connection_string)


# 2 TIME-BASED SPLIT: OBSERVATION WINDOW vs PREDICTION WINDOW
#
# Features are computed ONLY from transactions on or before CUTOFF_DATE
# (observation window). The target is the revenue a customer generates in
# the HORIZON_DAYS after the cutoff (prediction window).
#
# An earlier version computed features over the full timeline and used the
# same TotalRevenue as both a feature and the target. That is target leakage:
# the model scored deceptively well because the answer was in its inputs.
# Separating the windows in time removes it.

HORIZON_DAYS = 180

last_date = pd.read_sql(
    "SELECT MAX(InvoiceDate) AS d FROM Dim_Time", engine
)["d"].iloc[0]
last_date = pd.to_datetime(last_date)

CUTOFF_DATE = last_date - pd.Timedelta(days=HORIZON_DAYS)

print("Observation window ends :", CUTOFF_DATE.date())
print("Prediction window       :", CUTOFF_DATE.date(), "->", last_date.date())


FEATURE_QUERY = text("""
SELECT
    c.Customer_ID,
    COUNT(DISTINCT t.InvoiceDate)           AS PurchaseFrequency,
    SUM(f.Quantity * f.Price)               AS TotalRevenue,
    AVG(f.Quantity * f.Price)               AS AvgOrderValue,
    MAX(t.InvoiceDate)                      AS LastPurchaseDate,
    MIN(t.InvoiceDate)                      AS FirstPurchaseDate,
    COUNT(DISTINCT f.ProductKey)            AS UniqueProducts,
    COUNT(DISTINCT f.CountryKey)            AS CountriesPurchased
FROM Fact_Transactions f
JOIN Dim_Customers c ON f.CustomerKey = c.CustomerKey
JOIN Dim_Time t      ON f.TimeKey = t.TimeKey
WHERE f.Quantity > 0
  AND f.Price > 0
  AND t.InvoiceDate <= :as_of
GROUP BY c.Customer_ID
""")

TARGET_QUERY = text("""
SELECT
    c.Customer_ID,
    SUM(f.Quantity * f.Price) AS FutureRevenue
FROM Fact_Transactions f
JOIN Dim_Customers c ON f.CustomerKey = c.CustomerKey
JOIN Dim_Time t      ON f.TimeKey = t.TimeKey
WHERE f.Quantity > 0
  AND f.Price > 0
  AND t.InvoiceDate >  :start_date
  AND t.InvoiceDate <= :end_date
GROUP BY c.Customer_ID
""")


def build_features(as_of):
    """Customer features using only transactions up to `as_of`."""
    feats = pd.read_sql(FEATURE_QUERY, engine, params={"as_of": as_of})
    feats["LastPurchaseDate"] = pd.to_datetime(feats["LastPurchaseDate"])
    feats["FirstPurchaseDate"] = pd.to_datetime(feats["FirstPurchaseDate"])
    feats["RecencyDays"] = (as_of - feats["LastPurchaseDate"]).dt.days
    feats["TenureDays"] = (as_of - feats["FirstPurchaseDate"]).dt.days
    return feats.drop(columns=["LastPurchaseDate", "FirstPurchaseDate"])


# 3 TRAINING SET: features @ cutoff -> revenue in the following window

features = build_features(CUTOFF_DATE)

target = pd.read_sql(
    TARGET_QUERY,
    engine,
    params={"start_date": CUTOFF_DATE, "end_date": last_date},
)

# Customers with no purchases in the prediction window have a future value of 0
df = features.merge(target, on="Customer_ID", how="left")
df["FutureRevenue"] = df["FutureRevenue"].fillna(0.0)

print("Dataset Shape:", df.shape)
print(df.head())

print("\nTarget Variable Statistics (FutureRevenue)")
print(df["FutureRevenue"].describe())

plt.figure(figsize=(8, 5))
sns.histplot(df["FutureRevenue"], bins=50, kde=True)
plt.title("Customer Revenue in Prediction Window")
plt.xlabel("Future Revenue")
plt.ylabel("Number of Customers")
plt.show()


# 4 TRAIN / TEST SPLIT
# Features and target already sit in different time periods, so a customer-level
# split cannot leak the target through the features.

X = df.drop(columns=["Customer_ID", "FutureRevenue"])
y = df["FutureRevenue"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)


# 5 MACHINE LEARNING MODEL

model = RandomForestRegressor(
    n_estimators=200,
    max_depth=10,
    random_state=42
)

model.fit(X_train, y_train)


# 6 MODEL EVALUATION

predictions = model.predict(X_test)

mae = mean_absolute_error(y_test, predictions)
r2 = r2_score(y_test, predictions)

print("\nModel Performance (held-out customers, future window)")
print("MAE:", mae)
print("R2 Score:", r2)


# 7 ACTUAL VS PREDICTED VISUALIZATION

plt.figure(figsize=(7, 7))
plt.scatter(y_test, predictions, alpha=0.5)
plt.xlabel("Actual Future Revenue")
plt.ylabel("Predicted Future Revenue")
plt.title("Actual vs Predicted Future Customer Revenue")

plt.plot(
    [y_test.min(), y_test.max()],
    [y_test.min(), y_test.max()],
    color="red"
)

plt.show()


# 8 RESIDUAL ERROR ANALYSIS

residuals = y_test - predictions

plt.figure(figsize=(8, 5))
sns.histplot(residuals, bins=50, kde=True)
plt.title("Prediction Error Distribution")
plt.xlabel("Prediction Error")
plt.show()


# 9 FEATURE IMPORTANCE

importance = pd.Series(
    model.feature_importances_,
    index=X.columns
).sort_values(ascending=False)

print("\nFeature Importance:")
print(importance)

plt.figure(figsize=(8, 5))
sns.barplot(x=importance.values, y=importance.index)
plt.title("Feature Importance")
plt.show()


# 10 CUSTOMER LIFETIME VALUE PREDICTION
# Score every customer using features as of the latest date in the data,
# predicting their value over the NEXT HORIZON_DAYS.

scoring = build_features(last_date)
scoring["Predicted_CLV"] = model.predict(scoring[X.columns])

print(scoring.head())


# 11 CUSTOMER SEGMENTATION (CLV TIERS)
# rank(method="first") breaks ties so qcut always yields four equal-sized bins.

scoring["CLV_Segment"] = pd.qcut(
    scoring["Predicted_CLV"].rank(method="first"),
    q=4,
    labels=["Low Value", "Medium Value", "High Value", "VIP"]
)

print("\nCustomer Segment Distribution")
print(scoring["CLV_Segment"].value_counts())


# 12 SAVE PREDICTIONS BACK TO SQL

df_predictions = scoring[["Customer_ID", "Predicted_CLV", "CLV_Segment"]]

df_predictions.to_sql(
    "ML_Customer_CLV_Predictions",
    engine,
    if_exists="replace",
    index=False
)

print("\nPredictions exported to SQL Server.")
