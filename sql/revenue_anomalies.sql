WITH daily AS (
    SELECT
        c.customer_state,
        o.order_purchase_timestamp::date AS order_date,
        SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN customers c    ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1, 2
),
calendar AS (
    SELECT s.customer_state, d::date AS order_date
    FROM (SELECT DISTINCT customer_state FROM daily) s
    CROSS JOIN generate_series('2017-01-01'::date, '2018-08-31'::date, interval '1 day') AS d
),
filled AS (
    SELECT
        cal.customer_state,
        cal.order_date,
        COALESCE(d.revenue, 0) AS daily_revenue
    FROM calendar cal
    LEFT JOIN daily d
        ON d.customer_state = cal.customer_state
       AND d.order_date     = cal.order_date
),
stats AS (
    SELECT
        *,
        AVG(daily_revenue)    OVER w7  AS moving_avg_7,
        STDDEV(daily_revenue) OVER w30 AS moving_std_30
    FROM filled
    WINDOW
        w7  AS (PARTITION BY customer_state ORDER BY order_date
                ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING),
        w30 AS (PARTITION BY customer_state ORDER BY order_date
                ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)
)
SELECT
    customer_state,
    order_date,
    daily_revenue,
    ROUND(moving_avg_7, 2)  AS moving_avg_7,
    ROUND(moving_std_30, 2) AS moving_std_30,
    CASE
        WHEN moving_std_30 > 0 AND ABS(daily_revenue - moving_avg_7) > 2 * moving_std_30
            THEN CASE WHEN daily_revenue > moving_avg_7 THEN 'spike' ELSE 'drop' END
        ELSE 'normal'
    END AS day_type
FROM stats
WHERE order_date >= '2017-02-01'
ORDER BY customer_state, order_date;