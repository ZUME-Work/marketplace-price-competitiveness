"""Contested-product deep dive (fixed-effects regression) and charts.

Run after build_db.py:  python scripts/05_analysis.py
Writes outputs/tables/*.csv and outputs/charts/*.png
"""
from pathlib import Path

import duckdb
import matplotlib
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
TAB, CHART = ROOT / "outputs" / "tables", ROOT / "outputs" / "charts"
TAB.mkdir(parents=True, exist_ok=True)
CHART.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(ROOT / "marketplace.duckdb"), read_only=True)
for t in ["dq_checks", "m_coverage", "m_freight_distance", "m_freight_category",
          "m_contested_summary", "m_index_coverage", "m_price_index_category", "m_price_index_month"]:
    con.sql(f"SELECT * FROM {t}").df().to_csv(TAB / f"{t}.csv", index=False)
cs = con.sql("SELECT * FROM contested_sellers").df()
freight = con.sql("SELECT * FROM m_freight_category").df()
idx_cat = con.sql("SELECT * FROM m_price_index_category").df()
con.close()

# ---------------------------------------------------------------------------
# 1. What wins a contested product? Seller's share of a product-quarter's items
#    explained with product-quarter fixed effects (compares sellers of the SAME
#    product at the SAME time, so product popularity and season drop out).
# ---------------------------------------------------------------------------
cs["group"] = cs.product_id + "_" + cs.order_quarter.astype(str)
cs["landed_vs_median_pct"] = (
    cs.landed_price / cs.groupby("group").landed_price.transform("median") - 1) * 100
cs["is_cheapest_landed"] = (cs.landed_rank == 1).astype(int)
cs["share_pct"] = cs.item_share * 100
d = cs.dropna(subset=["review_score", "delivery_days"]).copy()
# Keep groups that still have 2+ sellers after dropping missing values
d = d[d.groupby("group").seller_id.transform("size") >= 2]

model = smf.ols(
    "share_pct ~ landed_vs_median_pct + review_score + delivery_days + same_state_share + C(group)",
    data=d,
).fit(cov_type="cluster", cov_kwds={"groups": d.product_id})
keep = ["landed_vs_median_pct", "review_score", "delivery_days", "same_state_share"]
labels = {
    "landed_vs_median_pct": "Landed price vs product median (+1 pct pt)",
    "review_score": "Average review score (+1 star)",
    "delivery_days": "Median delivery time (+1 day)",
    "same_state_share": "Share of orders shipped within the buyer's state (0 -> 1)",
}
coef = pd.DataFrame({
    "driver": [labels[k] for k in keep],
    "effect_on_share_pct_pts": model.params[keep].round(2).values,
    "ci_low": model.conf_int().loc[keep, 0].round(2).values,
    "ci_high": model.conf_int().loc[keep, 1].round(2).values,
    "p_value": model.pvalues[keep].round(3).values,
})
coef["n_seller_rows"] = len(d)
coef["n_product_quarters"] = d.group.nunique()
coef.to_csv(TAB / "contested_drivers.csv", index=False)
print(coef.to_string(index=False))

# Simple descriptive companion: share by landed-price gap to the cheapest seller
bins = [-0.001, 0.0, 0.05, 0.15, np.inf]
names = ["Cheapest", "0-5% above", "5-15% above", ">15% above"]
cs["gap_bucket"] = pd.cut(cs.gap_to_cheapest_landed, bins=bins, labels=names)
gap = cs.groupby("gap_bucket", observed=True).agg(
    seller_rows=("seller_id", "size"),
    avg_item_share_pct=("share_pct", "mean"),
    avg_review=("review_score", "mean"),
    median_delivery_days=("delivery_days", "median"),
).round(1).reset_index()
gap.to_csv(TAB / "contested_share_by_gap.csv", index=False)
print(gap.to_string(index=False))

# ---------------------------------------------------------------------------
# 2. Charts
# ---------------------------------------------------------------------------
BLUE, LIGHT, ORANGE = "#2b5c8a", "#9bb5cf", "#c97b3a"

# Freight share: same state vs cross state, top categories
f = freight.sort_values("freight_share_cross_state_pct")
fig, ax = plt.subplots(figsize=(8, 6))
y = np.arange(len(f))
ax.barh(y + 0.2, f.freight_share_cross_state_pct, 0.4, color=BLUE, label="Cross state")
ax.barh(y - 0.2, f.freight_share_same_state_pct, 0.4, color=LIGHT, label="Same state")
ax.set_yticks(y)
ax.set_yticklabels(f.category.str.replace("_", " "), fontsize=9)
ax.set_xlabel("Median freight as % of what the buyer pays (price + freight)")
ax.set_title("Shipping is 10-40% of the buyer's cost, and more when the seller is out of state", fontsize=10)
ax.legend(frameon=False, fontsize=8, loc="lower right")
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(CHART / "freight_share_by_category.png", dpi=150)

# Price-positioning index by category
c = idx_cat.sort_values("index_landed_sales_w")
fig, ax = plt.subplots(figsize=(8, 6))
y = np.arange(len(c))
ax.barh(y + 0.2, c.index_landed_sales_w, 0.4, color=BLUE, label="Sales-weighted")
ax.barh(y - 0.2, c.index_landed_capped5, 0.4, color=LIGHT, label="Sales-weighted, max 5 items per listing")
ax.axvline(0, c="#999", lw=1)
ax.set_yticks(y)
ax.set_yticklabels(c.category.str.replace("_", " "), fontsize=9)
ax.set_xlabel("Price-positioning index on landed price (% cheaper - % more expensive than peers)")
ax.set_title("Where buyers concentrate on cheaper-than-peer listings", fontsize=10)
ax.legend(frameon=False, fontsize=8, loc="lower right")
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(CHART / "price_index_by_category.png", dpi=150)

# Driver effects with confidence intervals
fig, ax = plt.subplots(figsize=(9.5, 3.8))
y = np.arange(len(coef))[::-1]
ax.errorbar(coef.effect_on_share_pct_pts, y,
            xerr=[coef.effect_on_share_pct_pts - coef.ci_low, coef.ci_high - coef.effect_on_share_pct_pts],
            fmt="o", color=BLUE, ecolor=LIGHT, capsize=3)
ax.axvline(0, c="#999", lw=1)
ax.set_yticks(y)
ax.set_yticklabels(coef.driver, fontsize=8.5)
ax.set_xlabel("Change in seller's share of the product's sales (pct points), 95% CI")
ax.set_title(f"What wins a contested product\n(same product, same quarter; n = {len(d):,} seller rows)", fontsize=10)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(CHART / "contested_drivers.png", dpi=150)
