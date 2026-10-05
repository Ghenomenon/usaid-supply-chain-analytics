"""
Late-delivery classification for USAID health-commodity shipments.

Every step that learns from the data (country grouping, freight-cost imputation,
scaling, encoding) is fitted on the training split only, inside the model pipeline.
The test split is touched once, for evaluation.

Results are reported at the default 0.5 probability cut-off. No threshold is tuned.
Balanced class weights make the models favour catching late shipments (recall)
over precision, because only 11.5% of shipments are late.
"""
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, TransformerMixin
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (average_precision_score, classification_report,
                             confusion_matrix, roc_auc_score)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

# --- Step 1: Load the SQL-validated, cleaned dataset ---
df = pd.read_csv("data/shipments_for_powerbi.csv")
print("Shape:", df.shape)

# Target: was this shipment delivered after its scheduled date?
df["is_late"] = (df["delay_days"] > 0).astype(int)
print("Late rate:", round(df["is_late"].mean(), 3))

# --- Step 2: Features known at ship time ---
# Excluded on purpose (leakage): delivered_to_client_date, delivery_recorded_date and
# delay_days are only known after delivery, i.e. after the outcome being predicted.
cat_cols = ["shipment_mode", "country", "product_group", "vendor_inco_term", "fulfill_via"]
num_cols = ["line_item_quantity", "pack_price", "unit_price", "freight_cost_numeric"]

X = df[cat_cols + num_cols]
y = df["is_late"]

# --- Step 3: Split first, so nothing below learns from the test rows ---
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y)
print(f"Train: {len(X_train)} rows, test: {len(X_test)} rows")


class GroupRareCategories(BaseEstimator, TransformerMixin):
    """Replace categories seen fewer than `min_count` times in TRAINING data with 'Other'."""

    def __init__(self, min_count=30):
        self.min_count = min_count

    def fit(self, X, y=None):
        X = pd.DataFrame(X)
        self.keep_ = {c: set(X[c].value_counts().loc[lambda s: s >= self.min_count].index)
                      for c in X.columns}
        return self

    def transform(self, X):
        X = pd.DataFrame(X).copy()
        for c, keep in self.keep_.items():
            X[c] = X[c].where(X[c].isin(keep), "Other")
        return X

    def get_feature_names_out(self, input_features=None):
        return np.asarray(input_features if input_features is not None else list(self.keep_))


categorical = Pipeline([
    # Missing shipment mode is informative in the EDA, so it becomes its own category.
    ("fill", SimpleImputer(strategy="constant", fill_value="Unknown")),
    ("to_frame", GroupRareCategories(min_count=1).set_output(transform="pandas")),
    ("onehot", OneHotEncoder(handle_unknown="ignore")),
])
country = Pipeline([
    ("fill", SimpleImputer(strategy="constant", fill_value="Unknown")),
    # Countries with fewer than 30 training shipments are grouped, as in the EDA and SQL work.
    ("group", GroupRareCategories(min_count=30).set_output(transform="pandas")),
    ("onehot", OneHotEncoder(handle_unknown="ignore")),
])
numeric = Pipeline([
    # Median from the training split only; the indicator keeps "freight cost missing" as a signal.
    ("impute", SimpleImputer(strategy="median", add_indicator=True)),
    ("scale", StandardScaler()),
])
preprocessor = ColumnTransformer([
    ("cat", categorical, [c for c in cat_cols if c != "country"]),
    ("country", country, ["country"]),
    ("num", numeric, num_cols),
]).set_output(transform="default")

# --- Step 4: Train two models ---
models = {
    "Logistic Regression": LogisticRegression(max_iter=2000, class_weight="balanced", random_state=42),
    "Random Forest": RandomForestClassifier(n_estimators=300, max_depth=8, class_weight="balanced",
                                            random_state=42, n_jobs=-1),
}
fitted = {}
for name, est in models.items():
    fitted[name] = Pipeline([("prep", preprocessor), ("model", est)]).fit(X_train, y_train)

# --- Step 5: Evaluate once on the held-out test split (0.5 cut-off) ---
results = []
for name, model in fitted.items():
    preds = model.predict(X_test)
    probs = model.predict_proba(X_test)[:, 1]
    tn, fp, fn, tp = confusion_matrix(y_test, preds).ravel()
    results.append({"model": name, "roc_auc": roc_auc_score(y_test, probs),
                    "pr_auc": average_precision_score(y_test, probs),
                    "recall_late": tp / (tp + fn), "precision_late": tp / (tp + fp),
                    "tp": tp, "fp": fp, "fn": fn, "tn": tn})
    print(f"\n=== {name} ===")
    print(classification_report(y_test, preds, target_names=["On time or early", "Late"]))
summary = pd.DataFrame(results)
print(summary.round(3).to_string(index=False))
summary.round(4).to_csv("model_results.csv", index=False)

# --- Step 6: Feature importance from the Random Forest ---
rf = fitted["Random Forest"]
names = rf.named_steps["prep"].get_feature_names_out()
imp = (pd.DataFrame({"feature": names, "importance": rf.named_steps["model"].feature_importances_})
       .sort_values("importance", ascending=False).head(15))
print("\nTop 15 features by Random Forest importance (predictive, not causal):")
print(imp.to_string(index=False))

fig, ax = plt.subplots(figsize=(8, 6))
ax.barh(imp["feature"][::-1], imp["importance"][::-1], color="#378ADD")
ax.set_xlabel("Feature importance")
ax.set_title("Top 15 predictors of late delivery (Random Forest)")
plt.tight_layout()
plt.savefig("plots/06_feature_importance.png", dpi=150)
print("\nSaved plots/06_feature_importance.png and model_results.csv")
