# delivery_time_dest.sql

`orders` + `customers` → **f** → **итоговый SELECT**

---

## CTE f

> Определяет **регион** по штату покупателя, считает **срок доставки в днях** и **число заказов** для каждой пары «регион × срок».

> **orders:**
> - `order_id`
> - `customer_id`
> - `order_status`
> - `order_purchase_timestamp`
> - `order_approved_at`
> - `order_delivered_carrier_date`
> - `order_delivered_customer_date`
> - `order_estimated_delivery_date`

> **customers:**
> - `customer_id`
> - `customer_unique_id`
> - `customer_zip_code_prefix`
> - `customer_city`
> - `customer_state`

> **f:**
> - `region`
> - `delivery_time`
> - `frequency`

```sql
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
```

- `CASE ... IN (...)` объединяет штаты в 5 регионов.
- Разность двух `timestamp` — это `interval`; `EXTRACT(DAY FROM ...)` берёт из него число полных дней.
- `GROUP BY 1, 2` — группировка по региону и сроку.

---

## Итоговый SELECT

> Переводит число заказов в **долю внутри региона**.

> **f:**
> - `region`
> - `delivery_time`
> - `frequency`

> **Результат:**
> - `region`
> - `delivery_time`
> - `share`

```sql
SELECT
	region,
	delivery_time,
	frequency::numeric / SUM(frequency) OVER (PARTITION BY region) AS share
FROM f
ORDER BY 1, 2;
```

- `SUM(frequency) OVER (PARTITION BY region)` — сумма заказов региона в каждой строке; сумма `share` по региону = 1.
- `::numeric` — чтобы деление не было целочисленным.
