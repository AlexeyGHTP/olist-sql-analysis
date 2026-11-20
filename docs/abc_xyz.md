# abc_xyz.sql

`order_items` + `orders` → **monthly** → **sellers** → **classified** → **labeled** → **итоговый SELECT**

---

## CTE monthly

> Считает **выручку каждого продавца по месяцам**.

> **order_items:**
> - `order_id`
> - `order_item_id`
> - `product_id`
> - `seller_id`
> - `shipping_limit_date`
> - `price`
> - `freight_value`

> **orders:**
> - `order_id`
> - `customer_id`
> - `order_status`
> - `order_purchase_timestamp`
> - `order_approved_at`
> - `order_delivered_carrier_date`
> - `order_delivered_customer_date`
> - `order_estimated_delivery_date`

> **monthly:**
> - `seller_id`
> - `month`
> - `month_revenue`

```sql
WITH monthly AS (
    SELECT
        oi.seller_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(oi.price) AS month_revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1, 2
)
```

- Строки есть только для месяцев, в которых у продавца были продажи.

---

## CTE sellers

> Для каждого продавца: **общая выручка**, **число месяцев с продажами** и **коэффициент вариации** помесячной выручки.

> **monthly:**
> - `seller_id`
> - `month`
> - `month_revenue`

> **sellers:**
> - `seller_id`
> - `total_revenue`
> - `active_months`
> - `cv`

```sql
sellers AS (
    SELECT
        seller_id,
        SUM(month_revenue) AS total_revenue,
        COUNT(*) AS active_months,
        STDDEV(month_revenue) / NULLIF(AVG(month_revenue), 0) AS cv
    FROM monthly
    GROUP BY seller_id
)
```

- `cv = STDDEV / AVG`.
- `NULLIF(x, 0)` возвращает `NULL` вместо 0 — защита от деления на ноль.
- При одном месяце `STDDEV` = `NULL`, поэтому и `cv` = `NULL`.

---

## CTE classified

> Считает **накопленную долю выручки** по продавцам, отсортированным по убыванию выручки.

> **sellers:**
> - `seller_id`
> - `total_revenue`
> - `active_months`
> - `cv`

> **classified:**
> - `seller_id`
> - `total_revenue`
> - `active_months`
> - `cv`
> - `cum_share`

```sql
classified AS (
    SELECT
        *,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC, seller_id)
          / SUM(total_revenue) OVER () AS cum_share
    FROM sellers
)
```

- `SUM(...) OVER (ORDER BY ...)` — накопительная сумма.
- `SUM(...) OVER ()` — сумма по всей таблице.
- `seller_id` в `ORDER BY` нужен при равной выручке: без него строки с одинаковым значением получили бы одинаковую накопленную сумму.

---

## CTE labeled

> Присваивает продавцу **класс ABC** по `cum_share` и **класс XYZ** по `cv`.

> **classified:**
> - `seller_id`
> - `total_revenue`
> - `active_months`
> - `cv`
> - `cum_share`

> **labeled:**
> - `seller_id`
> - `total_revenue`
> - `abc`
> - `xyz`

```sql
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
            WHEN cv < 0.5   THEN 'X'
            WHEN cv <= 1    THEN 'Y'
            ELSE 'Z'
        END AS xyz
    FROM classified
)
```

- `cv IS NULL` проверяется первым: сравнение с `NULL` даёт `NULL`, и такие строки иначе попали бы в `ELSE` (класс Z).

---

## Итоговый SELECT

> Для каждой комбинации ABC × XYZ: **число продавцов, выручка и доля выручки**.

> **labeled:**
> - `seller_id`
> - `total_revenue`
> - `abc`
> - `xyz`

> **Результат:**
> - `abc`
> - `xyz`
> - `sellers`
> - `revenue`
> - `revenue_share_pct`

```sql
SELECT
    abc,
    xyz,
    COUNT(*)                   AS sellers,
    ROUND(SUM(total_revenue))  AS revenue,
    ROUND(100.0 * SUM(total_revenue) / SUM(SUM(total_revenue)) OVER (), 1) AS revenue_share_pct
FROM labeled
GROUP BY abc, xyz
ORDER BY abc, xyz;
```

- `SUM(SUM(total_revenue)) OVER ()` — оконная сумма поверх агрегата: внутренний `SUM` — выручка группы, внешний — сумма всех групп. Работает, потому что оконные функции выполняются после `GROUP BY`.
