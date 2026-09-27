import pandas as pd

# --- Step 1: Load the SQL-validated, cleaned dataset ---
df = pd.read_csv("data/shipments_for_powerbi.csv")

print("Shape:", df.shape)
print("\nColumns:", list(df.columns))
print("\nMissing values (top 10):")
print(df.isna().sum().sort_values(ascending=False).head(10))

# Target: was this shipment delivered late?
df["is_late"] = (df["delay_days"] > 0).astype(int)
print("\nTarget distribution:")
print(df["is_late"].value_counts(normalize=True).round(3))

# --- Step 2: Feature engineering ---
# Excluded on purpose (leakage): delivered_to_client_date, delivery_recorded_date,
# delay_days -- these are only known AFTER delivery, i.e. after the outcome
# we're predicting. Only features knowable at ship time go in.

candidate_categoricals = ["shipment_mode", "country", "product_group",
                           "vendor_inco_term", "fulfill_via", "managed_by"]
print("\n--- Cardinality of candidate categorical features ---")
for c in candidate_categoricals:
    print(f"{c}: {df[c].nunique()} unique values")

# Country has too many rare categories to one-hot encode cleanly -- group
# anything below the same n>=30 threshold used in the EDA/SQL work into 'Other'.
country_counts = df["country"].value_counts()
frequent_countries = country_counts[country_counts >= 30].index
df["country_grouped"] = df["country"].where(df["country"].isin(frequent_countries), "Other")
print(f"\nCountries kept individually: {len(frequent_countries)}, rest grouped into 'Other'")

# Missing shipment_mode and missing freight_cost are informative on their own
# (found in EDA to correlate with lateness/cost) -- keep as explicit categories/flags
# rather than dropping or silently imputing them away.
df["shipment_mode"] = df["shipment_mode"].fillna("Unknown")
df["freight_missing"] = df["freight_cost_numeric"].isna().astype(int)
df["freight_cost_filled"] = df["freight_cost_numeric"].fillna(df["freight_cost_numeric"].median())

feature_cols_cat = ["shipment_mode", "country_grouped", "product_group",
                     "vendor_inco_term", "fulfill_via"]
feature_cols_num = ["line_item_quantity", "pack_price", "unit_price",
                     "freight_cost_filled", "freight_missing"]

print("\nFinal feature set:")
print("Categorical:", feature_cols_cat)
print("Numeric:", feature_cols_num)

# --- Step 3: Train/test split + preprocessing pipeline ---
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.pipeline import Pipeline

X = df[feature_cols_cat + feature_cols_num]
y = df["is_late"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)
print(f"\nTrain: {X_train.shape[0]} rows, Test: {X_test.shape[0]} rows")
print("Train target rate:", round(y_train.mean(), 3), "| Test target rate:", round(y_test.mean(), 3))

preprocessor = ColumnTransformer(transformers=[
    ("cat", OneHotEncoder(handle_unknown="ignore"), feature_cols_cat),
    ("num", StandardScaler(), feature_cols_num),
])

# --- Step 4: Train two models ---
# class_weight="balanced" matters here: only 11.5% of shipments are late,
# so an unweighted model could just predict "never late" and still be 88.5% "accurate".
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier

log_reg = Pipeline([
    ("prep", preprocessor),
    ("model", LogisticRegression(max_iter=1000, class_weight="balanced", random_state=42)),
])
log_reg.fit(X_train, y_train)
print("Logistic Regression trained.")

rf = Pipeline([
    ("prep", preprocessor),
    ("model", RandomForestClassifier(n_estimators=300, max_depth=8,
                                      class_weight="balanced", random_state=42, n_jobs=-1)),
])
rf.fit(X_train, y_train)
print("Random Forest trained.")

# --- Step 5: Evaluate on held-out test set ---
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score

for name, model in [("Logistic Regression", log_reg), ("Random Forest", rf)]:
    preds = model.predict(X_test)
    probs = model.predict_proba(X_test)[:, 1]
    print(f"\n=== {name} ===")
    print(classification_report(y_test, preds, target_names=["On-time/early", "Late"]))
    print("ROC-AUC:", round(roc_auc_score(y_test, probs), 3))
    print("Confusion matrix [[TN FP] [FN TP]]:")
    print(confusion_matrix(y_test, preds))

# --- Step 6: Feature importance from the Random Forest (the stronger model) ---
import matplotlib.pyplot as plt

feature_names = rf.named_steps["prep"].get_feature_names_out()
importances = rf.named_steps["model"].feature_importances_
importance_df = pd.DataFrame({"feature": feature_names, "importance": importances})
importance_df = importance_df.sort_values("importance", ascending=False).head(15)

print("\n--- Top 15 features driving late-delivery predictions ---")
print(importance_df.to_string(index=False))

fig, ax = plt.subplots(figsize=(8, 6))
ax.barh(importance_df["feature"][::-1], importance_df["importance"][::-1], color="#378ADD")
ax.set_xlabel("Feature importance")
ax.set_title("Top 15 predictors of late delivery (Random Forest)")
plt.tight_layout()
plt.savefig("plots/06_feature_importance.png", dpi=150)
print("\nSaved plots/06_feature_importance.png")
