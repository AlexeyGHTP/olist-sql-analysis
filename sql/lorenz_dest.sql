WITH seller_rev AS (
    SELECT oi.seller_id, SUM(oi.price) AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY oi.seller_id
),
lorenz AS (
    SELECT
        seller_id,
        revenue,
        ROW_NUMBER() OVER (ORDER BY revenue, seller_id)::numeric
            / COUNT(*) OVER ()                                AS cum_sellers,
        SUM(revenue) OVER (ORDER BY revenue, seller_id)
            / SUM(revenue) OVER ()                            AS cum_revenue
    FROM seller_rev
)
SELECT * FROM lorenz ORDER BY cum_sellers;