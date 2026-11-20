"""Download the Olist Brazilian E-Commerce tables used here into data/raw/.

Source: Olist, "Brazilian E-Commerce Public Dataset by Olist" (Kaggle), licence CC BY-NC-SA 4.0.
Files are fetched from Olist's own public GitHub repository.
"""
from pathlib import Path
import urllib.request

BASE = "https://raw.githubusercontent.com/olist/work-at-olist-data/master/datasets/"
FILES = ["olist_orders_dataset.csv", "olist_order_items_dataset.csv", "olist_products_dataset.csv",
         "olist_sellers_dataset.csv", "olist_customers_dataset.csv", "olist_order_reviews_dataset.csv",
         "product_category_name_translation.csv"]
OUT = Path(__file__).resolve().parents[1] / "data" / "raw"

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for f in FILES:
        urllib.request.urlretrieve(BASE + f, OUT / f)
        print(f"saved {f} ({(OUT / f).stat().st_size / 1e6:.1f} MB)")
