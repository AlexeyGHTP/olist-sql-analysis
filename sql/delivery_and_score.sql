WITH last_review AS (
    SELECT order_id, review_score
    FROM (
        SELECT order_id, review_score,
               ROW_NUMBER() OVER (PARTITION BY order_id
                                  ORDER BY review_creation_date DESC,
                                           review_answer_timestamp DESC) AS rn
        FROM order_reviews
    ) r
    WHERE rn = 1
),
delivered AS (
    SELECT
        o.order_id,
        o.order_delivered_customer_date::date
          - o.order_estimated_delivery_date::date AS delay_days,
        r.review_score
    FROM orders o
    JOIN last_review r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
bas AS (
    SELECT *,
        CASE
            WHEN delay_days < -7 THEN '1_early_8plus'
            WHEN delay_days <= 0 THEN '2_early_0_7'
            WHEN delay_days <= 3 THEN '3_late_1_3'
            WHEN delay_days <= 7 THEN '4_late_4_7'
            ELSE                      '5_late_8plus'
        END AS basket
    FROM delivered
)
SELECT
    basket,
    COUNT(*)                                                             AS orders,
    ROUND(AVG(review_score), 2)                                          AS avg_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS low_score_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score = 5)  / COUNT(*), 2) AS high_score_pct
FROM bas
GROUP BY basket
ORDER BY basket;



WITH last_review AS (
    SELECT order_id, review_score
    FROM (
        SELECT order_id, review_score,
               ROW_NUMBER() OVER (PARTITION BY order_id
                                  ORDER BY review_creation_date DESC,
                                           review_answer_timestamp DESC) AS rn
        FROM order_reviews
    ) r
    WHERE rn = 1
),
delivered AS (
    SELECT
        o.order_id,
        o.order_delivered_customer_date::date
          - o.order_estimated_delivery_date::date AS delay_days,
        r.review_score
    FROM orders o
    JOIN last_review r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
, late_cat AS (
    SELECT DISTINCT
        d.order_id,
        d.review_score,
        COALESCE(t.product_category_name_english, p.product_category_name) AS category
    FROM delivered d
    JOIN order_items oi ON oi.order_id = d.order_id
    JOIN products p     ON p.product_id = oi.product_id
    LEFT JOIN product_category_name_translation t
           ON t.product_category_name = p.product_category_name
    WHERE d.delay_days > 0
      AND p.product_category_name IS NOT NULL
)
SELECT
    category,
    COUNT(*) AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS low_score_pct
FROM late_cat
GROUP BY category
HAVING COUNT(*) >= 100
ORDER BY low_score_pct DESC
LIMIT 5;