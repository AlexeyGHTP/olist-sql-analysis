# products_pairs.sql

В файле два запроса:

1. `order_items` → **multi_item** → **order_cat** → **multi** → **total** / **cat_orders** / **pairs** → **metrics** → **итоговый SELECT**
2. те же CTE до **metrics** → **top10** → **pair_orders** → **pair_payments** (+ `payments`) → **type_rank** / **installments** → **итоговый SELECT**

---

# Запрос 1

## CTE multi_item

> Находит заказы, в которых **больше одной позиции**.

> **order_items:**
> - `order_id`
> - `order_item_id`
> - `product_id`
> - `seller_id`
> - `shipping_limit_date`
> - `price`
> - `freight_value`

> **multi_item:**
> - `order_id`

```sql
WITH multi_item AS (
    SELECT order_id
    FROM order_items
    WHERE order_item_id = 2
)
```

- `order_item_id` — номер позиции в заказе (1, 2, 3…). Есть позиция №2 → в заказе минимум 2 товара. Каждый такой заказ попадает в результат ровно один раз.

---

## CTE order_cat

> Для этих заказов получает **уникальные категории товаров** в каждом заказе.

> **multi_item:**
> - `order_id`

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

> **products:**
> - `product_id`
> - `product_category_name`
> - `product_name_lenght`
> - `product_description_lenght`
> - `product_photos_qty`
> - `product_weight_g`
> - `product_length_cm`
> - `product_height_cm`
> - `product_width_cm`

> **product_category_name_translation:**
> - `product_category_name`
> - `product_category_name_english`

> **order_cat:**
> - `order_id`
> - `category`

```sql
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
)
```

- `DISTINCT` — одна строка на пару «заказ × категория».
- `LEFT JOIN` + `COALESCE` — английское название, если есть перевод, иначе исходное.

---

## CTE multi

> Оставляет заказы, где **2 и больше разных категорий**.

> **order_cat:**
> - `order_id`
> - `category`

> **multi:**
> - `order_id`

```sql
multi AS (
    SELECT order_id
    FROM order_cat
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
```

---

## CTE total

> Считает **число таких заказов**.

> **multi:**
> - `order_id`

> **total:**
> - `n_total`

```sql
total AS (
    SELECT COUNT(*) AS n_total FROM multi
)
```

---

## CTE cat_orders

> Для каждой категории считает **число заказов из `multi`**, в которых она есть.

> **order_cat:**
> - `order_id`
> - `category`

> **multi:**
> - `order_id`

> **cat_orders:**
> - `category`
> - `n_cat`

```sql
cat_orders AS (
    SELECT oc.category, COUNT(*) AS n_cat
    FROM order_cat oc
    JOIN multi m ON m.order_id = oc.order_id
    GROUP BY oc.category
)
```

- `JOIN multi` — считаются только заказы с 2+ категориями, как и в `total`.

---

## CTE pairs

> Составляет **все пары категорий внутри заказа** и считает число заказов для каждой пары.

> **order_cat:**
> - `order_id`
> - `category`

> **pairs:**
> - `cat_a`
> - `cat_b`
> - `n_pair`

```sql
pairs AS (
    SELECT a.category AS cat_a, b.category AS cat_b, COUNT(*) AS n_pair
    FROM order_cat a
    JOIN order_cat b
      ON b.order_id = a.order_id
     AND a.category < b.category
    GROUP BY 1, 2
)
```

- Self-join: таблица соединяется сама с собой по `order_id`.
- `a.category < b.category` убирает пары категории с самой собой и зеркальные дубли (`A + B` и `B + A`).

---

## CTE metrics

> Считает для каждой пары **support, confidence A→B, confidence B→A и lift**.

> **pairs:**
> - `cat_a`
> - `cat_b`
> - `n_pair`

> **total:**
> - `n_total`

> **cat_orders:**
> - `category`
> - `n_cat`

> **metrics:**
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `support`
> - `conf_a_to_b`
> - `conf_b_to_a`
> - `lift`

```sql
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
```

- `CROSS JOIN total` — в `total` одна строка, `n_total` просто добавляется к каждой паре.
- `cat_orders` присоединяется дважды (`ca`, `cb`) — для первой и второй категории пары.

---

## Итоговый SELECT (запрос 1)

> Выводит пары с `n_pair >= 5` и `lift > 1`, по убыванию lift.

> **metrics:**
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `support`
> - `conf_a_to_b`
> - `conf_b_to_a`
> - `lift`

> **Результат:**
> - `pair`
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `support_pct`
> - `conf_a_to_b_pct`
> - `conf_b_to_a_pct`
> - `lift`

```sql
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
```

- `||` — склейка строк.

---

# Запрос 2

CTE `multi_item`, `order_cat`, `multi`, `total`, `cat_orders`, `pairs` такие же, как в запросе 1. В `metrics` считается только `lift`:

```sql
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
)
```

---

## CTE top10

> Берёт **10 пар с наибольшим lift**.

> **metrics:**
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `lift`

> **top10:**
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `lift`

```sql
top10 AS (
    SELECT cat_a, cat_b, n_pair, lift
    FROM metrics
    WHERE n_pair >= 5 AND lift > 1
    ORDER BY lift DESC
    LIMIT 10
)
```

---

## CTE pair_orders

> Находит **заказы, в которых встретилась каждая пара** из топ-10.

> **top10:**
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `lift`

> **order_cat:**
> - `order_id`
> - `category`

> **pair_orders:**
> - `cat_a`
> - `cat_b`
> - `order_id`

```sql
pair_orders AS (
    SELECT t.cat_a, t.cat_b, a.order_id
    FROM top10 t
    JOIN order_cat a ON a.category = t.cat_a
    JOIN order_cat b ON b.order_id = a.order_id
                    AND b.category = t.cat_b
)
```

- Первый `JOIN` — заказы с `cat_a`, второй оставляет из них те, где в том же заказе есть `cat_b`.

---

## CTE pair_payments

> Для каждого заказа берёт **один платёж с наибольшей суммой** — его тип и число платежей рассрочки.

> **pair_orders:**
> - `cat_a`
> - `cat_b`
> - `order_id`

> **payments:**
> - `order_id`
> - `payment_sequential`
> - `payment_type`
> - `payment_installments`
> - `payment_value`

> **pair_payments:**
> - `cat_a`
> - `cat_b`
> - `payment_type`
> - `payment_installments`

```sql
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
)
```

- У заказа может быть несколько платежей; обычный `JOIN` размножил бы строки.
- `CROSS JOIN LATERAL (... LIMIT 1)` — подзапрос выполняется для каждого заказа и возвращает одну строку.

---

## CTE type_rank

> Нумерует **типы оплаты по частоте** внутри каждой пары.

> **pair_payments:**
> - `cat_a`
> - `cat_b`
> - `payment_type`
> - `payment_installments`

> **type_rank:**
> - `cat_a`
> - `cat_b`
> - `payment_type`
> - `rn`

```sql
type_rank AS (
    SELECT
        cat_a, cat_b, payment_type,
        ROW_NUMBER() OVER (PARTITION BY cat_a, cat_b
                           ORDER BY COUNT(*) DESC, payment_type) AS rn
    FROM pair_payments
    GROUP BY cat_a, cat_b, payment_type
)
```

- Сначала `GROUP BY` считает `COUNT(*)` по типу оплаты, затем `ROW_NUMBER()` нумерует типы внутри пары по убыванию количества. `rn = 1` — самый частый тип.

---

## CTE installments

> Считает **среднее число платежей рассрочки** по каждой паре.

> **pair_payments:**
> - `cat_a`
> - `cat_b`
> - `payment_type`
> - `payment_installments`

> **installments:**
> - `cat_a`
> - `cat_b`
> - `avg_inst`

```sql
installments AS (
    SELECT cat_a, cat_b, AVG(payment_installments) AS avg_inst
    FROM pair_payments
    GROUP BY cat_a, cat_b
)
```

---

## Итоговый SELECT (запрос 2)

> Собирает для каждой пары из топ-10 **lift, самый частый тип оплаты и среднюю рассрочку**.

> **top10:**
> - `cat_a`
> - `cat_b`
> - `n_pair`
> - `lift`

> **type_rank:**
> - `cat_a`
> - `cat_b`
> - `payment_type`
> - `rn`

> **installments:**
> - `cat_a`
> - `cat_b`
> - `avg_inst`

> **Результат:**
> - `pair`
> - `n_pair`
> - `lift`
> - `top_payment_type`
> - `avg_installments`

```sql
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
```

- `tr.rn = 1` в условии `ON` оставляет из `type_rank` одну строку на пару.
