-- 01_data_quality.sql
-- Count every known trap before deciding exclusions. Output: dq_checks.
CREATE OR REPLACE TABLE dq_checks AS
SELECT 'order_items_rows' AS check_name, count(*) AS n FROM raw_order_items
UNION ALL SELECT 'orders_rows', count(*) FROM raw_orders
UNION ALL SELECT 'orders_canceled_or_unavailable', count(*) FROM raw_orders WHERE order_status IN ('canceled', 'unavailable')
UNION ALL SELECT 'orders_delivered_without_delivery_date', count(*) FROM raw_orders
  WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
UNION ALL SELECT 'duplicate_order_item_keys', count(*) - count(DISTINCT (order_id, order_item_id)) FROM raw_order_items
UNION ALL SELECT 'items_price_le_zero', count(*) FROM raw_order_items WHERE price <= 0
UNION ALL SELECT 'items_free_freight', count(*) FROM raw_order_items WHERE freight_value = 0
UNION ALL SELECT 'products_without_category', count(*) FROM raw_products WHERE product_category_name IS NULL
UNION ALL SELECT 'products_without_weight', count(*) FROM raw_products WHERE coalesce(product_weight_g, 0) = 0
UNION ALL SELECT 'categories_without_english_name', count(DISTINCT p.product_category_name)
  FROM raw_products p LEFT JOIN raw_category_en t USING (product_category_name)
  WHERE p.product_category_name IS NOT NULL AND t.product_category_name_english IS NULL
-- Fan-out trap: some orders have more than one review row
UNION ALL SELECT 'orders_with_multiple_reviews', count(*) FROM (
  SELECT order_id FROM raw_reviews GROUP BY 1 HAVING count(*) > 1);
