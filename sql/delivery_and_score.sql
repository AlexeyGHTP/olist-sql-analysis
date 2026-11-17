WITH last_review AS (
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC, review_answer_timestamp DESC
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
    COUNT(*) AS orders,
    ROUND(AVG(review_score), 2) AS avg_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS low_score_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score = 5)  / COUNT(*), 2) AS high_score_pct
FROM bas
GROUP BY basket
ORDER BY basket;



WITH late AS (
    SELECT o.order_id
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date
),
late_scored AS (
    SELECT l.order_id, r.review_score
    FROM late l
    CROSS JOIN LATERAL (
        SELECT rv.review_score
        FROM order_reviews rv
        WHERE rv.order_id = l.order_id
        ORDER BY rv.review_creation_date DESC, rv.review_answer_timestamp DESC
        LIMIT 1
    ) r
),
late_cat AS (
    SELECT DISTINCT
        ls.order_id,
        ls.review_score,
        COALESCE(t.product_category_name_english, p.product_category_name) AS category
    FROM late_scored ls
    JOIN order_items oi ON oi.order_id = ls.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN product_category_name_translation t
           ON t.product_category_name = p.product_category_name
    WHERE p.product_category_name IS NOT NULL
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
