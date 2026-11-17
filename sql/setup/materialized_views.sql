--Когортный анализ удержания
DROP MATERIALIZED VIEW IF EXISTS mv_cohort_retention;

CREATE MATERIALIZED VIEW mv_cohort_retention AS
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

CREATE UNIQUE INDEX ON mv_cohort_retention (cohort_month, month_idx);

COMMENT ON MATERIALIZED VIEW mv_cohort_retention IS 'Когортный анализ удержания';


-- Аномалии дневной выручки по штатам
DROP MATERIALIZED VIEW IF EXISTS mv_revenue_anomalies;

CREATE MATERIALIZED VIEW mv_revenue_anomalies AS
WITH daily AS (
    SELECT
        c.customer_state,
        o.order_purchase_timestamp::date AS order_date,
        SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
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
       AND d.order_date = cal.order_date
),
stats AS (
    SELECT
        *,
        AVG(daily_revenue) OVER w7  AS moving_avg_7,
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
    ROUND(moving_avg_7, 2) AS moving_avg_7,
    ROUND(moving_std_30, 2) AS moving_std_30,
    CASE
        WHEN moving_std_30 > 0 AND ABS(daily_revenue - moving_avg_7) > 2 * moving_std_30
            THEN CASE WHEN daily_revenue > moving_avg_7 THEN 'spike' ELSE 'drop' END
        ELSE 'normal'
    END AS day_type
FROM stats
WHERE order_date >= '2017-02-01'
ORDER BY customer_state, order_date;

CREATE UNIQUE INDEX ON mv_revenue_anomalies (customer_state, order_date);

COMMENT ON MATERIALIZED VIEW mv_revenue_anomalies IS 'Аномалии дневной выручки по штатам';


-- Задержка доставки и оценка
DROP MATERIALIZED VIEW IF EXISTS mv_delivery_score;

CREATE MATERIALIZED VIEW mv_delivery_score AS
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
            ELSE '5_late_8plus'
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

CREATE UNIQUE INDEX ON mv_delivery_score (basket);

COMMENT ON MATERIALIZED VIEW mv_delivery_score IS 'Задержка доставки и оценка: по группам задержки';


-- Категории с наибольшей долей низких оценок
DROP MATERIALIZED VIEW IF EXISTS mv_delivery_low_score_category;

CREATE MATERIALIZED VIEW mv_delivery_low_score_category AS
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

CREATE UNIQUE INDEX ON mv_delivery_low_score_category (category);

COMMENT ON MATERIALIZED VIEW mv_delivery_low_score_category IS 'Задержка доставки: категории с наибольшей долей низких оценок';


-- ABC/XYZ
DROP MATERIALIZED VIEW IF EXISTS mv_abc_xyz;

CREATE MATERIALIZED VIEW mv_abc_xyz AS
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
        SUM(month_revenue) AS total_revenue,
        COUNT(*) AS active_months,
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
            WHEN cv IS NULL THEN 'N/A'
            WHEN cv < 0.5 THEN 'X'
            WHEN cv <= 1 THEN 'Y'
            ELSE 'Z'
        END AS xyz
    FROM classified
)
SELECT
    abc,
    xyz,
    COUNT(*) AS sellers,
    ROUND(SUM(total_revenue)) AS revenue,
    ROUND(100.0 * SUM(total_revenue) / SUM(SUM(total_revenue)) OVER (), 1) AS revenue_share_pct
FROM labeled
GROUP BY abc, xyz
ORDER BY abc, xyz;

CREATE UNIQUE INDEX ON mv_abc_xyz (abc, xyz);

COMMENT ON MATERIALIZED VIEW mv_abc_xyz IS 'ABC/XYZ-анализ продавцов';


-- Анализ корзины
DROP MATERIALIZED VIEW IF EXISTS mv_product_pairs;

CREATE MATERIALIZED VIEW mv_product_pairs AS
WITH multi_item AS (
    SELECT order_id
    FROM order_items
    WHERE order_item_id = 2
),
order_cat AS (
    SELECT DISTINCT
        oi.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name) AS category
    FROM multi_item mi
    JOIN order_items oi ON oi.order_id = mi.order_id
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN product_category_name_translation t
           ON t.product_category_name = p.product_category_name
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND p.product_category_name IS NOT NULL
),
multi AS (
    SELECT order_id
    FROM order_cat
    GROUP BY order_id
    HAVING COUNT(*) > 1
),
total AS (
    SELECT COUNT(*) AS n_total FROM multi
),
cat_orders AS (
    SELECT oc.category, COUNT(*) AS n_cat
    FROM order_cat oc
    JOIN multi m ON m.order_id = oc.order_id
    GROUP BY oc.category
),
pairs AS (
    SELECT a.category AS cat_a, b.category AS cat_b, COUNT(*) AS n_pair
    FROM order_cat a
    JOIN order_cat b
      ON b.order_id = a.order_id
     AND a.category < b.category
    GROUP BY 1, 2
),
metrics AS (
    SELECT
        p.cat_a,
        p.cat_b,
        p.n_pair,
        p.n_pair::numeric / t.n_total AS support,
        p.n_pair::numeric / ca.n_cat AS conf_a_to_b,
        p.n_pair::numeric / cb.n_cat AS conf_b_to_a,
        p.n_pair::numeric * t.n_total / (ca.n_cat * cb.n_cat) AS lift
    FROM pairs p
    CROSS JOIN total t
    JOIN cat_orders ca ON ca.category = p.cat_a
    JOIN cat_orders cb ON cb.category = p.cat_b
)
SELECT
    cat_a || ' + ' || cat_b AS pair,
    cat_a,
    cat_b,
    n_pair,
    ROUND(support * 100, 2) AS support_pct,
    ROUND(conf_a_to_b * 100, 2) AS conf_a_to_b_pct,
    ROUND(conf_b_to_a * 100, 2) AS conf_b_to_a_pct,
    ROUND(lift, 2) AS lift
FROM metrics
WHERE n_pair >= 5
  AND lift > 1
ORDER BY lift DESC;

CREATE UNIQUE INDEX ON mv_product_pairs (cat_a, cat_b);

COMMENT ON MATERIALIZED VIEW mv_product_pairs IS 'Анализ корзины: пары категорий';


-- Анализ корзины: оплата в топ-10 пар
DROP MATERIALIZED VIEW IF EXISTS mv_product_pairs_top_ten;

CREATE MATERIALIZED VIEW mv_product_pairs_top_ten AS
WITH multi_item AS (
    SELECT order_id
    FROM order_items
    WHERE order_item_id = 2
),
order_cat AS (
    SELECT DISTINCT
        oi.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name) AS category
    FROM multi_item mi
    JOIN order_items oi ON oi.order_id = mi.order_id
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN product_category_name_translation t
           ON t.product_category_name = p.product_category_name
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND p.product_category_name IS NOT NULL
),
multi AS (
    SELECT order_id
    FROM order_cat
    GROUP BY order_id
    HAVING COUNT(*) > 1
),
total AS (
    SELECT COUNT(*) AS n_total FROM multi
),
cat_orders AS (
    SELECT oc.category, COUNT(*) AS n_cat
    FROM order_cat oc
    JOIN multi m ON m.order_id = oc.order_id
    GROUP BY oc.category
),
pairs AS (
    SELECT a.category AS cat_a, b.category AS cat_b, COUNT(*) AS n_pair
    FROM order_cat a
    JOIN order_cat b
      ON b.order_id = a.order_id
     AND a.category < b.category
    GROUP BY 1, 2
),
metrics AS (
    SELECT
        p.cat_a,
        p.cat_b,
        p.n_pair,
        p.n_pair::numeric * t.n_total / (ca.n_cat * cb.n_cat) AS lift
    FROM pairs p
    CROSS JOIN total t
    JOIN cat_orders ca ON ca.category = p.cat_a
    JOIN cat_orders cb ON cb.category = p.cat_b
),
top10 AS (
    SELECT cat_a, cat_b, n_pair, lift
    FROM metrics
    WHERE n_pair >= 5 AND lift > 1
    ORDER BY lift DESC
    LIMIT 10
),
pair_orders AS (
    SELECT t.cat_a, t.cat_b, a.order_id
    FROM top10 t
    JOIN order_cat a ON a.category = t.cat_a
    JOIN order_cat b ON b.order_id = a.order_id
                    AND b.category = t.cat_b
),
pair_payments AS (
    SELECT po.cat_a, po.cat_b, mp.payment_type, mp.payment_installments
    FROM pair_orders po
    CROSS JOIN LATERAL (
        SELECT pm.payment_type, pm.payment_installments
        FROM payments pm
        WHERE pm.order_id = po.order_id
        ORDER BY pm.payment_value DESC, pm.payment_sequential
        LIMIT 1
    ) mp
),
type_rank AS (
    SELECT
        cat_a, cat_b, payment_type,
        ROW_NUMBER() OVER (PARTITION BY cat_a, cat_b
                           ORDER BY COUNT(*) DESC, payment_type) AS rn
    FROM pair_payments
    GROUP BY cat_a, cat_b, payment_type
),
installments AS (
    SELECT cat_a, cat_b, AVG(payment_installments) AS avg_inst
    FROM pair_payments
    GROUP BY cat_a, cat_b
)
SELECT
    t.cat_a || ' + ' || t.cat_b AS pair,
    t.n_pair,
    ROUND(t.lift, 2) AS lift,
    tr.payment_type AS top_payment_type,
    ROUND(i.avg_inst, 2) AS avg_installments
FROM top10 t
JOIN type_rank tr   ON tr.cat_a = t.cat_a AND tr.cat_b = t.cat_b AND tr.rn = 1
JOIN installments i ON i.cat_a = t.cat_a AND i.cat_b = t.cat_b
ORDER BY t.lift DESC;

CREATE UNIQUE INDEX ON mv_product_pairs_top_ten (pair);

COMMENT ON MATERIALIZED VIEW mv_product_pairs_top_ten IS 'Анализ корзины: оплата в топ-10 пар';


-- Распределение времени доставки по регионам
DROP MATERIALIZED VIEW IF EXISTS mv_delivery_time_dest;

CREATE MATERIALIZED VIEW mv_delivery_time_dest AS
WITH f AS (SELECT
    CASE 
        WHEN c.customer_state IN ('ES', 'MG', 'RJ', 'SP') THEN 'Southeast'
        WHEN c.customer_state IN ('PR', 'RS', 'SC') THEN 'South'
        WHEN c.customer_state IN ('DF', 'GO', 'MS', 'MT') THEN 'Central-West'
        WHEN c.customer_state IN ('AL', 'BA', 'CE', 'MA', 'PB', 'PE', 'PI', 'RN', 'SE') THEN 'Northeast'
        WHEN c.customer_state IN ('AC', 'AM', 'AP', 'PA', 'RO', 'RR', 'TO') THEN 'North'
    END AS region,
    EXTRACT(DAY FROM o.order_delivered_customer_date - o.order_purchase_timestamp) AS delivery_time,
    COUNT(*) AS frequency
FROM orders AS o
LEFT JOIN customers AS c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY 1, 2
)
SELECT
    region,
    delivery_time,
    frequency::numeric / SUM(frequency) OVER (PARTITION BY region) AS share
FROM f
ORDER BY 1, 2;

CREATE UNIQUE INDEX ON mv_delivery_time_dest (region, delivery_time);

COMMENT ON MATERIALIZED VIEW mv_delivery_time_dest IS 'Распределение времени доставки по регионам (доля заказов по дням)';


-- Кривая Лоренца
DROP MATERIALIZED VIEW IF EXISTS mv_lorenz;

CREATE MATERIALIZED VIEW mv_lorenz AS
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
            / COUNT(*) OVER () AS cum_sellers,
        SUM(revenue) OVER (ORDER BY revenue, seller_id)
            / SUM(revenue) OVER () AS cum_revenue
    FROM seller_rev
)
SELECT * FROM lorenz ORDER BY cum_sellers;

CREATE UNIQUE INDEX ON mv_lorenz (seller_id);

COMMENT ON MATERIALIZED VIEW mv_lorenz IS 'Кривая Лоренца: накопленные доли продавцов и выручки';


REFRESH MATERIALIZED VIEW CONCURRENTLY mv_cohort_retention;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_revenue_anomalies;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_delivery_score;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_delivery_low_score_category;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_abc_xyz;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_pairs;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_pairs_top_ten;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_delivery_time_dest;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_lorenz;


SELECT matviewname,
       pg_size_pretty(pg_total_relation_size(format('%I', matviewname)::regclass)) AS size
FROM pg_matviews
WHERE schemaname = 'public'
ORDER BY matviewname;
