# lorenz_dest.sql

`order_items` + `orders` → **seller_rev** → **lorenz** → **итоговый SELECT**

---

## CTE seller_rev

> Считает **общую выручку каждого продавца**.

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

> **seller_rev:**
> - `seller_id`
> - `revenue`

```sql
WITH seller_rev AS (
    SELECT oi.seller_id, SUM(oi.price) AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY oi.seller_id
)
```

- `JOIN` с `orders` нужен только для фильтра по статусу.

---

## CTE lorenz

> Для каждого продавца (по возрастанию выручки) считает **накопленную долю продавцов** и **накопленную долю выручки**.

> **seller_rev:**
> - `seller_id`
> - `revenue`

> **lorenz:**
> - `seller_id`
> - `revenue`
> - `cum_sellers`
> - `cum_revenue`

```sql
lorenz AS (
    SELECT
        seller_id,
        revenue,
        ROW_NUMBER() OVER (ORDER BY revenue, seller_id)::numeric
            / COUNT(*) OVER ()                                AS cum_sellers,
        SUM(revenue) OVER (ORDER BY revenue, seller_id)
            / SUM(revenue) OVER ()                            AS cum_revenue
    FROM seller_rev
)
```

- `ROW_NUMBER() / COUNT(*) OVER ()` — номер строки / всего строк = накопленная доля продавцов.
- `SUM(...) OVER (ORDER BY ...) / SUM(...) OVER ()` — накопительная сумма / общая сумма.
- `::numeric` — чтобы деление целых чисел не дало 0.
- `seller_id` в `ORDER BY` — для однозначного порядка при равной выручке.

---

## Итоговый SELECT

> Выводит все строки по порядку `cum_sellers`.

> **lorenz:**
> - `seller_id`
> - `revenue`
> - `cum_sellers`
> - `cum_revenue`

> **Результат:**
> - `seller_id`
> - `revenue`
> - `cum_sellers`
> - `cum_revenue`

```sql
SELECT * FROM lorenz ORDER BY cum_sellers;
```
