# cohort_retention.sql

`orders` + `customers` → **valid_orders** → **activity** → **agg** → **итоговый SELECT**

---

## CTE valid_orders

> Подготавливает список **успешных заказов** с привязкой к уникальному **клиенту** и расчетными полями **месяца** для дальнейшего анализа удержания (Retention) или когортного анализа.

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

> **valid_orders:**
> - `customer_unique_id`
> - `order_month`
> - `month_num`

```sql
WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
        (EXTRACT(YEAR FROM o.order_purchase_timestamp)::int * 12
         + EXTRACT(MONTH FROM o.order_purchase_timestamp)::int) AS month_num
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
)
```

- `DATE_TRUNC('month', ...)::date` — дата обрезается до первого дня месяца.
- `month_num = год * 12 + месяц` — сквозной номер месяца; разность двух таких номеров даёт число месяцев между датами.

---

## CTE activity

> Для каждого клиента определяет **месяц первого заказа** (когорту) и оставляет по одной строке на каждый **месяц, в котором у клиента были заказы**.

> **valid_orders:**
> - `customer_unique_id`
> - `order_month`
> - `month_num`

> **activity:**
> - `customer_unique_id`
> - `month_num`
> - `cohort_month`
> - `cohort_num`

```sql
activity AS (
    SELECT DISTINCT
        customer_unique_id,
        month_num,
        MIN(order_month) OVER (PARTITION BY customer_unique_id) AS cohort_month,
        MIN(month_num) OVER (PARTITION BY customer_unique_id) AS cohort_num
    FROM valid_orders
)
```

- `MIN(...) OVER (PARTITION BY customer_unique_id)` — минимум по всем заказам клиента, проставленный в каждую его строку (строки не схлопываются, в отличие от `GROUP BY`).
- `DISTINCT` убирает дубли, если у клиента несколько заказов в одном месяце.

---

## CTE agg

> Считает число **активных клиентов** в каждой когорте по номеру месяца от первой покупки (0–12).

> **activity:**
> - `customer_unique_id`
> - `month_num`
> - `cohort_month`
> - `cohort_num`

> **agg:**
> - `cohort_month`
> - `month_idx`
> - `active_customers`

```sql
agg AS (
    SELECT cohort_month, month_num - cohort_num AS month_idx, COUNT(*) AS active_customers
    FROM activity
    WHERE month_num - cohort_num <= 12
    GROUP BY 1, 2
)
```

- `month_idx = month_num - cohort_num`: `0` — месяц первого заказа, `1` — следующий и т. д.
- `GROUP BY 1, 2` — группировка по номерам колонок в `SELECT`.

---

## Итоговый SELECT

> Считает **процент удержания**: активные клиенты месяца / размер когорты (клиенты в месяце 0).

> **agg:**
> - `cohort_month`
> - `month_idx`
> - `active_customers`

> **Результат:**
> - `cohort_month`
> - `month_idx`
> - `active_customers`
> - `retention_pct`

```sql
SELECT
    cohort_month,
    month_idx,
    active_customers,
    ROUND(100.0 * active_customers
          / MAX(active_customers) FILTER (WHERE month_idx = 0)
            OVER (PARTITION BY cohort_month), 2) AS retention_pct
FROM agg
ORDER BY cohort_month, month_idx;
```

- `MAX(...) FILTER (WHERE month_idx = 0) OVER (PARTITION BY cohort_month)` — берёт значение месяца 0 и проставляет его во все строки когорты; это знаменатель.
- `100.0` вместо `100` — чтобы деление было дробным, а не целочисленным.
