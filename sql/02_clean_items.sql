-- 02_clean_items.sql
-- Item-level fact table. Grain: one row per order item (one unit sold).
-- Excludes canceled / unavailable orders. Reviews are averaged per order FIRST,
-- so an order with two review rows does not duplicate its items.
CREATE OR REPLACE TABLE order_review AS
SELECT order_id, avg(review_score) AS review_score
FROM raw_reviews
GROUP BY order_id;

CREATE OR REPLACE TABLE items AS
SELECT
      oi.order_id
    , oi.order_item_id
    , oi.product_id
    , oi.seller_id
    , o.order_purchase_timestamp                                     AS purchased_at
    , date_trunc('month',   o.order_purchase_timestamp)::date        AS order_month
    , date_trunc('quarter', o.order_purchase_timestamp)::date        AS order_quarter
    , coalesce(t.product_category_name_english,
               p.product_category_name, 'unknown')                   AS category
    , p.product_weight_g                                             AS weight_g
    , CASE
        WHEN coalesce(p.product_weight_g, 0) = 0 THEN 'unknown'
        WHEN p.product_weight_g <  500  THEN '1) <0.5kg'
        WHEN p.product_weight_g < 2000  THEN '2) 0.5-2kg'
        WHEN p.product_weight_g < 5000  THEN '3) 2-5kg'
        ELSE                                 '4) 5kg+'
      END                                                            AS weight_band
    , oi.price
    , oi.freight_value                                               AS freight
    , oi.price + oi.freight_value                                    AS landed_price
    , oi.freight_value / (oi.price + oi.freight_value)               AS freight_share
    , s.seller_state
    , c.customer_state
    , s.seller_state = c.customer_state                              AS same_state
    , o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL AS is_delivered
    , date_diff('day', o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days
    , o.order_delivered_customer_date > o.order_estimated_delivery_date AS is_late
    , r.review_score
FROM raw_order_items oi
JOIN raw_orders      o USING (order_id)
JOIN raw_products    p USING (product_id)
JOIN raw_sellers     s USING (seller_id)
JOIN raw_customers   c USING (customer_id)
LEFT JOIN raw_category_en t USING (product_category_name)
LEFT JOIN order_review    r USING (order_id)
WHERE TRUE
  AND o.order_status NOT IN ('canceled', 'unavailable');
