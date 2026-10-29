WITH order_cat AS (
    SELECT DISTINCT
        oi.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name) AS category
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
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
        p.n_pair::numeric / t.n_total                          AS support,
        p.n_pair::numeric / ca.n_cat                           AS conf_a_to_b,
        p.n_pair::numeric / cb.n_cat                           AS conf_b_to_a,
        p.n_pair::numeric * t.n_total / (ca.n_cat * cb.n_cat)  AS lift
    FROM pairs p
    CROSS JOIN total t
    JOIN cat_orders ca ON ca.category = p.cat_a
    JOIN cat_orders cb ON cb.category = p.cat_b
)
SELECT
    cat_a || ' + ' || cat_b     AS pair,
    cat_a,
    cat_b,
    n_pair,
    ROUND(support * 100, 2)     AS support_pct,
    ROUND(conf_a_to_b * 100, 2) AS conf_a_to_b_pct,
    ROUND(conf_b_to_a * 100, 2) AS conf_b_to_a_pct,
    ROUND(lift, 2)              AS lift
FROM metrics
WHERE n_pair >= 5
  AND lift > 1
ORDER BY lift DESC;



WITH order_cat AS (
    SELECT DISTINCT
        oi.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name) AS category
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
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
main_payment AS (
    SELECT order_id, payment_type, payment_installments
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY order_id
                                  ORDER BY payment_value DESC, payment_sequential) AS rn
        FROM payments
    ) x
    WHERE rn = 1
),
type_rank AS (
    SELECT
        po.cat_a, po.cat_b, mp.payment_type,
        ROW_NUMBER() OVER (PARTITION BY po.cat_a, po.cat_b
                           ORDER BY COUNT(*) DESC, mp.payment_type) AS rn
    FROM pair_orders po
    JOIN main_payment mp ON mp.order_id = po.order_id
    GROUP BY po.cat_a, po.cat_b, mp.payment_type
),
installments AS (
    SELECT po.cat_a, po.cat_b, AVG(mp.payment_installments) AS avg_inst
    FROM pair_orders po
    JOIN main_payment mp ON mp.order_id = po.order_id
    GROUP BY po.cat_a, po.cat_b
)
SELECT
    t.cat_a || ' + ' || t.cat_b AS pair,
    t.n_pair,
    ROUND(t.lift, 2)            AS lift,
    tr.payment_type             AS top_payment_type,
    ROUND(i.avg_inst, 2)        AS avg_installments
FROM top10 t
JOIN type_rank tr   ON tr.cat_a = t.cat_a AND tr.cat_b = t.cat_b AND tr.rn = 1
JOIN installments i ON i.cat_a = t.cat_a AND i.cat_b = t.cat_b
ORDER BY t.lift DESC;