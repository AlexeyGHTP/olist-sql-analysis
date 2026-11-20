# revenue_anomalies.sql

`orders` + `order_items` + `customers` → **daily** → **calendar** → **filled** → **stats** → **итоговый SELECT**

---

## CTE daily

> Считает **выручку по каждому штату за каждый день** в период с 2017-01-01 по 2018-08-31.

> **orders:**
> - `order_id`
> - `customer_id`
> - `order_status`
> - `order_purchase_timestamp`
> - `order_approved_at`
> - `order_delivered_carrier_date`
> - `order_delivered_customer_date`
> - `order_estimated_delivery_date`

> **order_items:**
> - `order_id`
> - `order_item_id`
> - `product_id`
> - `seller_id`
> - `shipping_limit_date`
> - `price`
> - `freight_value`

> **customers:**
> - `customer_id`
> - `customer_unique_id`
> - `customer_zip_code_prefix`
> - `customer_city`
> - `customer_state`

> **daily:**
> - `customer_state`
> - `order_date`
> - `revenue`

```sql
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
)
```

- `::date` отбрасывает время, чтобы группировать по дням.
- `< '2018-09-01'` вместо `<= '2018-08-31'` захватывает весь последний день вместе со временем.

---

## CTE calendar

> Строит **все комбинации «штат × день»** за период.

> **daily:**
> - `customer_state`
> - `order_date`
> - `revenue`

> **calendar:**
> - `customer_state`
> - `order_date`

```sql
calendar AS (
    SELECT s.customer_state, d::date AS order_date
    FROM (SELECT DISTINCT customer_state FROM daily) s
    CROSS JOIN generate_series('2017-01-01'::date, '2018-08-31'::date, interval '1 day') AS d
)
```

- `generate_series(начало, конец, шаг)` генерирует все даты периода.
- `CROSS JOIN` умножает список штатов на список дат.
- Нужен, потому что в `daily` нет строк для дней без заказов.

---

## CTE filled

> Присоединяет выручку к календарю; **дни без заказов получают 0**.

> **calendar:**
> - `customer_state`
> - `order_date`

> **daily:**
> - `customer_state`
> - `order_date`
> - `revenue`

> **filled:**
> - `customer_state`
> - `order_date`
> - `daily_revenue`

```sql
filled AS (
    SELECT
        cal.customer_state,
        cal.order_date,
        COALESCE(d.revenue, 0) AS daily_revenue
    FROM calendar cal
    LEFT JOIN daily d
        ON d.customer_state = cal.customer_state
       AND d.order_date = cal.order_date
)
```

- `LEFT JOIN` от календаря сохраняет все дни.
- `COALESCE(d.revenue, 0)` заменяет `NULL` на 0.

---

## CTE stats

> Считает для каждого дня **скользящее среднее за 7 предыдущих дней** и **скользящее стандартное отклонение за 30 предыдущих дней**.

> **filled:**
> - `customer_state`
> - `order_date`
> - `daily_revenue`

> **stats:**
> - `customer_state`
> - `order_date`
> - `daily_revenue`
> - `moving_avg_7`
> - `moving_std_30`

```sql
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
```

- `WINDOW w7 AS (...)` — окно объявляется один раз и используется по имени.
- `ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING` — 7 строк до текущей, сама текущая строка в окно не входит.
- `PARTITION BY customer_state` — окна считаются отдельно по каждому штату.

---

## Итоговый SELECT

> Помечает каждый день как `spike`, `drop` или `normal`: аномалия — отклонение от среднего больше 2 стандартных отклонений.

> **stats:**
> - `customer_state`
> - `order_date`
> - `daily_revenue`
> - `moving_avg_7`
> - `moving_std_30`

> **Результат:**
> - `customer_state`
> - `order_date`
> - `daily_revenue`
> - `moving_avg_7`
> - `moving_std_30`
> - `day_type`

```sql
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
```

- Вложенный `CASE` определяет направление отклонения.
- `moving_std_30 > 0` — защита от случая, когда в окне одни нули.
- `WHERE order_date >= '2017-02-01'` отбрасывает январь, где окна ещё неполные. Фильтр стоит здесь, а не в `daily`, чтобы январские дни участвовали в окнах февраля.
