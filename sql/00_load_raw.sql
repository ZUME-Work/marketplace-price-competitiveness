-- 00_load_raw.sql
-- Load the raw Olist CSVs as-is.
CREATE OR REPLACE TABLE raw_orders      AS SELECT * FROM read_csv('data/raw/olist_orders_dataset.csv',        auto_detect = true);
CREATE OR REPLACE TABLE raw_order_items AS SELECT * FROM read_csv('data/raw/olist_order_items_dataset.csv',   auto_detect = true);
CREATE OR REPLACE TABLE raw_products    AS SELECT * FROM read_csv('data/raw/olist_products_dataset.csv',      auto_detect = true);
CREATE OR REPLACE TABLE raw_sellers     AS SELECT * FROM read_csv('data/raw/olist_sellers_dataset.csv',       auto_detect = true);
CREATE OR REPLACE TABLE raw_customers   AS SELECT * FROM read_csv('data/raw/olist_customers_dataset.csv',     auto_detect = true);
CREATE OR REPLACE TABLE raw_reviews     AS SELECT * FROM read_csv('data/raw/olist_order_reviews_dataset.csv', auto_detect = true);
CREATE OR REPLACE TABLE raw_category_en AS SELECT * FROM read_csv('data/raw/product_category_name_translation.csv', auto_detect = true);
