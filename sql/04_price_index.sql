-- 04_price_index.sql
-- Marketplace-wide price positioning, covering every sale (not only the 5% contested slice).
--
-- Listing-month = one product sold by one seller in one month, at its median price.
-- Peer group    = same category x weight band x month, with at least 10 listings.
-- Position      = listing price / peer median: Cheaper < 0.95, Equal 0.95-1.05, More expensive > 1.05.
-- Index         = %Cheaper - %More expensive, computed two ways:
--   equal-weighted: every listing counts once. ~0 by construction around a median, so on its own
--                   it says nothing about competitiveness.
--   sales-weighted: listings weighted by items sold. Above 0 means buyers concentrate on
--                   below-median-priced listings, i.e. the category is price-sensitive.
-- Built on item price AND on landed price (price + freight), which is what the buyer pays.
CREATE OR REPLACE TABLE listing_month AS
SELECT
      product_id, seller_id, order_month, category, weight_band
    , count(*)              AS items
    , median(price)         AS price
    , median(landed_price)  AS landed_price
FROM items_w
WHERE category <> 'unknown' AND weight_band <> 'unknown'
GROUP BY ALL;

CREATE OR REPLACE TABLE listing_position AS
WITH peer AS (
    SELECT category, weight_band, order_month
         , count(*)              AS peer_listings
         , median(price)         AS peer_price
         , median(landed_price)  AS peer_landed
    FROM listing_month GROUP BY ALL
    HAVING count(*) >= 10
)
SELECT
      l.*
    , p.peer_listings
    , l.price / p.peer_price           AS rel_price
    , l.landed_price / p.peer_landed   AS rel_landed
    , CASE WHEN l.price / p.peer_price < 0.95 THEN 'cheaper'
           WHEN l.price / p.peer_price > 1.05 THEN 'expensive' ELSE 'equal' END        AS pos_price
    , CASE WHEN l.landed_price / p.peer_landed < 0.95 THEN 'cheaper'
           WHEN l.landed_price / p.peer_landed > 1.05 THEN 'expensive' ELSE 'equal' END AS pos_landed
FROM listing_month l
JOIN peer p USING (category, weight_band, order_month);

-- Coverage of the index
CREATE OR REPLACE TABLE m_index_coverage AS
SELECT
      (SELECT count(*) FROM items_w)                         AS items_in_window
    , (SELECT sum(items) FROM listing_position)              AS items_in_index
    , round((SELECT sum(items) FROM listing_position) * 100.0 / (SELECT count(*) FROM items_w), 1) AS pct_items_covered
    , (SELECT count(*) FROM listing_position)                AS listing_months;

-- Index by category (top 15 by items)
CREATE OR REPLACE TABLE m_price_index_category AS
WITH top AS (SELECT category FROM listing_position GROUP BY 1 ORDER BY sum(items) DESC LIMIT 15)
SELECT
      category
    , sum(items)                                                                     AS items
    , count(*)                                                                       AS listing_months
    , round((avg((pos_price = 'cheaper')::int) - avg((pos_price = 'expensive')::int)) * 100, 1)   AS index_price_equal_w
    , round((sum(items * (pos_price = 'cheaper')::int) - sum(items * (pos_price = 'expensive')::int)) * 100.0 / sum(items), 1) AS index_price_sales_w
    , round((sum(items * (pos_landed = 'cheaper')::int) - sum(items * (pos_landed = 'expensive')::int)) * 100.0 / sum(items), 1) AS index_landed_sales_w
    -- Robustness: cap each listing-month's weight at 5 items so a few bestsellers cannot drive the index
    , round((sum(least(items, 5) * (pos_landed = 'cheaper')::int) - sum(least(items, 5) * (pos_landed = 'expensive')::int)) * 100.0 / sum(least(items, 5)), 1) AS index_landed_capped5
FROM listing_position JOIN top USING (category)
GROUP BY 1
ORDER BY index_landed_sales_w DESC;

-- Index over time (whole marketplace)
CREATE OR REPLACE TABLE m_price_index_month AS
SELECT
      order_month
    , sum(items) AS items
    , round((avg((pos_price = 'cheaper')::int) - avg((pos_price = 'expensive')::int)) * 100, 1)   AS index_price_equal_w
    , round((sum(items * (pos_price = 'cheaper')::int) - sum(items * (pos_price = 'expensive')::int)) * 100.0 / sum(items), 1) AS index_price_sales_w
    , round((sum(items * (pos_landed = 'cheaper')::int) - sum(items * (pos_landed = 'expensive')::int)) * 100.0 / sum(items), 1) AS index_landed_sales_w
FROM listing_position
GROUP BY 1 ORDER BY 1;
