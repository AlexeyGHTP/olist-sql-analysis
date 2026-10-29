WITH monthly AS (
    SELECT
        oi.seller_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(oi.price) AS month_revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1, 2
),
sellers AS (
    SELECT
        seller_id,
        SUM(month_revenue)                                    AS total_revenue,
        COUNT(*)                                              AS active_months,
        STDDEV(month_revenue) / NULLIF(AVG(month_revenue), 0) AS cv
    FROM monthly
    GROUP BY seller_id
),
classified AS (
    SELECT
        *,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC, seller_id)
          / SUM(total_revenue) OVER () AS cum_share
    FROM sellers
),
labeled AS (
    SELECT
        seller_id,
        total_revenue,
        CASE
            WHEN cum_share <= 0.80 THEN 'A'
            WHEN cum_share <= 0.95 THEN 'B'
            ELSE 'C'
        END AS abc,
        CASE
            WHEN cv IS NULL THEN 'N/A'   -- один месяц продаж
            WHEN cv < 0.5   THEN 'X'
            WHEN cv <= 1    THEN 'Y'
            ELSE 'Z'
        END AS xyz
    FROM classified
)
SELECT
    abc,
    xyz,
    COUNT(*)                   AS sellers,
    ROUND(SUM(total_revenue))  AS revenue,
    ROUND(100.0 * SUM(total_revenue) / SUM(SUM(total_revenue)) OVER (), 1) AS revenue_share_pct
FROM labeled
GROUP BY abc, xyz
ORDER BY abc, xyz;