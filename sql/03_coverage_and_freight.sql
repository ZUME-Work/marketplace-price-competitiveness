-- 03_coverage_and_freight.sql
-- Analysis window: 2017-01 to 2018-08. 2016 is sparse (349 items, no November) and
-- 2018-09 has one item, so both are left out of every metric from here on.
CREATE OR REPLACE VIEW items_w AS
SELECT * FROM items
WHERE order_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01';

-- Q1. How much of the marketplace has seller-vs-seller competition at all?
CREATE OR REPLACE TABLE m_coverage AS
WITH p AS (
    SELECT product_id, count(DISTINCT seller_id) AS n_sellers, count(*) AS items
    FROM items_w GROUP BY 1
), pq AS (   -- competition at the same time: same product, same quarter
    SELECT product_id, order_quarter, count(DISTINCT seller_id) AS n_sellers, count(*) AS items
    FROM items_w GROUP BY 1, 2
)
SELECT 'products with 1 seller (whole window)' AS measure, count(*) AS products, sum(items) AS items,
       round(sum(items) * 100.0 / (SELECT count(*) FROM items_w), 1) AS pct_of_items
FROM p WHERE n_sellers = 1
UNION ALL
SELECT 'products with 2+ sellers (whole window)', count(*), sum(items),
       round(sum(items) * 100.0 / (SELECT count(*) FROM items_w), 1)
FROM p WHERE n_sellers >= 2
UNION ALL
SELECT 'product-quarters with 2+ sellers (same time)', count(*), sum(items),
       round(sum(items) * 100.0 / (SELECT count(*) FROM items_w), 1)
FROM pq WHERE n_sellers >= 2;

-- Q2. Freight: how much of what the customer pays is shipping, and what does distance cost?
CREATE OR REPLACE TABLE m_freight_category AS
WITH top AS (
    SELECT category FROM items_w GROUP BY 1 ORDER BY count(*) DESC LIMIT 15
)
SELECT
      i.category
    , count(*)                                                        AS items
    , round(median(i.price), 1)                                       AS median_price_brl
    , round(median(i.freight_share) * 100, 1)                         AS median_freight_share_pct
    , round(median(i.freight_share) FILTER (WHERE i.same_state) * 100, 1)     AS freight_share_same_state_pct
    , round(median(i.freight_share) FILTER (WHERE NOT i.same_state) * 100, 1) AS freight_share_cross_state_pct
    , round(avg(i.same_state::int) * 100, 1)                          AS pct_items_same_state
FROM items_w i JOIN top USING (category)
GROUP BY 1
ORDER BY items DESC;

CREATE OR REPLACE TABLE m_freight_distance AS
SELECT
      CASE WHEN same_state THEN 'Same state' ELSE 'Cross state' END   AS route
    , count(*)                                                        AS items
    , round(median(freight_share) * 100, 1)                           AS median_freight_share_pct
    , round(median(freight), 1)                                       AS median_freight_brl
    , round(median(delivery_days) FILTER (WHERE is_delivered), 1)     AS median_delivery_days
    , round(avg(is_late::int) FILTER (WHERE is_delivered) * 100, 1)   AS late_pct
    , round(avg(review_score), 2)                                     AS avg_review
FROM items_w GROUP BY 1 ORDER BY 1;

-- Q3. In contested product-quarters, is the cheapest seller on item price also cheapest
--     on what the customer actually pays (price + freight)?
CREATE OR REPLACE TABLE contested_sellers AS
WITH sp AS (
    SELECT
          product_id, order_quarter, seller_id
        , any_value(category)                    AS category
        , count(*)                               AS items
        , median(price)                          AS price
        , median(landed_price)                   AS landed_price
        , avg(review_score)                      AS review_score
        , median(delivery_days) FILTER (WHERE is_delivered) AS delivery_days
        , avg(same_state::int)                   AS same_state_share
    FROM items_w GROUP BY 1, 2, 3
)
SELECT
      *
    , count(*)    OVER w                         AS n_sellers
    , sum(items)  OVER w                         AS group_items
    , items * 1.0 / sum(items) OVER w            AS item_share
    , rank() OVER (PARTITION BY product_id, order_quarter ORDER BY price)        AS price_rank
    , rank() OVER (PARTITION BY product_id, order_quarter ORDER BY landed_price) AS landed_rank
    , price        / min(price)        OVER w - 1 AS gap_to_cheapest_price
    , landed_price / min(landed_price) OVER w - 1 AS gap_to_cheapest_landed
FROM sp
WINDOW w AS (PARTITION BY product_id, order_quarter)
QUALIFY count(*) OVER w >= 2;

CREATE OR REPLACE TABLE m_contested_summary AS
WITH g AS (
    SELECT product_id, order_quarter
         , max(n_sellers) AS n_sellers
         , bool_or(price_rank = 1 AND landed_rank > 1) AS cheapest_item_not_cheapest_landed
    FROM contested_sellers GROUP BY 1, 2
)
SELECT
      (SELECT count(*) FROM g)                                         AS contested_product_quarters
    , (SELECT count(*) FROM contested_sellers)                         AS seller_rows
    , (SELECT round(avg(cheapest_item_not_cheapest_landed::int) * 100, 1) FROM g) AS pct_groups_cheapest_flips_on_landed
    , (SELECT round(sum(items) FILTER (WHERE price_rank = 1)  * 100.0 / sum(items), 1) FROM contested_sellers) AS share_items_cheapest_on_price
    , (SELECT round(sum(items) FILTER (WHERE landed_rank = 1) * 100.0 / sum(items), 1) FROM contested_sellers) AS share_items_cheapest_on_landed
    , (SELECT round(avg(1.0 / n_sellers) * 100, 1) FROM g)              AS even_split_share_pct
    , (SELECT round(median(gap_to_cheapest_price) * 100, 1) FROM contested_sellers WHERE price_rank > 1) AS median_gap_non_cheapest_pct;
