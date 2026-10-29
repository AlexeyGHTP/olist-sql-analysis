WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
cohorts AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM valid_orders
    GROUP BY customer_unique_id
),
activity AS (
    SELECT DISTINCT
        v.customer_unique_id,
        c.cohort_month,
        ((EXTRACT(YEAR  FROM v.order_month) - EXTRACT(YEAR  FROM c.cohort_month)) * 12
        + EXTRACT(MONTH FROM v.order_month) - EXTRACT(MONTH FROM c.cohort_month))::int AS month_idx
    FROM valid_orders v
    JOIN cohorts c ON c.customer_unique_id = v.customer_unique_id
),
agg AS (
    SELECT cohort_month, month_idx, COUNT(*) AS active_customers
    FROM activity
    WHERE month_idx <= 12
    GROUP BY cohort_month, month_idx
)
SELECT
    cohort_month,
    month_idx,
    active_customers,
    ROUND(100.0 * active_customers
          / MAX(active_customers) FILTER (WHERE month_idx = 0)
            OVER (PARTITION BY cohort_month), 2) AS retention_pct
FROM agg
ORDER BY cohort_month, month_idx;