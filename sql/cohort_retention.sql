WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
        (EXTRACT(YEAR FROM o.order_purchase_timestamp)::int * 12
         + EXTRACT(MONTH FROM o.order_purchase_timestamp)::int) AS month_num
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
activity AS (
    SELECT DISTINCT
        customer_unique_id,
        month_num,
        MIN(order_month) OVER (PARTITION BY customer_unique_id) AS cohort_month,
        MIN(month_num) OVER (PARTITION BY customer_unique_id) AS cohort_num
    FROM valid_orders
),
agg AS (
    SELECT cohort_month, month_num - cohort_num AS month_idx, COUNT(*) AS active_customers
    FROM activity
    WHERE month_num - cohort_num <= 12
    GROUP BY 1, 2
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