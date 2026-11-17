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


