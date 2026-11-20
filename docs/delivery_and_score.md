# delivery_and_score.sql

В файле два запроса:

1. `order_reviews` → **last_review** → **delivered** (+ `orders`) → **bas** → **итоговый SELECT**
2. `orders` → **late** → **late_scored** (+ `order_reviews`) → **late_cat** (+ `order_items`, `products`, `product_category_name_translation`) → **итоговый SELECT**

---

# Запрос 1

## CTE last_review

> Оставляет **один последний отзыв** на каждый заказ.

> **order_reviews:**
> - `review_id`
> - `order_id`
> - `review_score`
> - `review_comment_title`
> - `review_comment_message`
> - `review_creation_date`
> - `review_answer_timestamp`

> **last_review:**
> - `order_id`
> - `review_score`

```sql
WITH last_review AS (
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC, review_answer_timestamp DESC
)
```

- `DISTINCT ON (order_id)` (PostgreSQL) берёт первую строку в каждой группе `order_id` по порядку из `ORDER BY`.
- Сортировка по дате `DESC` → первая строка = последний отзыв.
- `ORDER BY` должен начинаться с колонок из `DISTINCT ON`.

---

## CTE delivered

> Для доставленных заказов считает **задержку в днях** (факт − обещанная дата) и подтягивает оценку.

> **orders:**
> - `order_id`
> - `customer_id`
> - `order_status`
> - `order_purchase_timestamp`
> - `order_approved_at`
> - `order_delivered_carrier_date`
> - `order_delivered_customer_date`
> - `order_estimated_delivery_date`

> **last_review:**
> - `order_id`
> - `review_score`

> **delivered:**
> - `order_id`
> - `delay_days`
> - `review_score`

```sql
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
)
```

- Разность двух `date` в PostgreSQL — целое число дней. Отрицательное — раньше срока, положительное — опоздание.
- `JOIN` (inner) отбрасывает заказы без отзыва.

---

## CTE bas

> Раскладывает заказы по **пяти группам задержки**.

> **delivered:**
> - `order_id`
> - `delay_days`
> - `review_score`

> **bas:**
> - `order_id`
> - `delay_days`
> - `review_score`
> - `basket`

```sql
bas AS (
    SELECT *,
        CASE
            WHEN delay_days < -7 THEN '1_early_8plus'
            WHEN delay_days <= 0 THEN '2_early_0_7'
            WHEN delay_days <= 3 THEN '3_late_1_3'
            WHEN delay_days <= 7 THEN '4_late_4_7'
            ELSE                      '5_late_8plus'
        END AS basket
    FROM delivered
)
```

- `CASE` проверяет условия сверху вниз, поэтому у каждой ветки достаточно верхней границы.
- Числовой префикс в названии нужен для правильной сортировки `ORDER BY basket`.

---

## Итоговый SELECT (запрос 1)

> По каждой группе: **число заказов, средняя оценка, доля оценок 1–2 и доля оценок 5**.

> **bas:**
> - `order_id`
> - `delay_days`
> - `review_score`
> - `basket`

> **Результат:**
> - `basket`
> - `orders`
> - `avg_score`
> - `low_score_pct`
> - `high_score_pct`

```sql
SELECT
    basket,
    COUNT(*) AS orders,
    ROUND(AVG(review_score), 2) AS avg_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS low_score_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score = 5)  / COUNT(*), 2) AS high_score_pct
FROM bas
GROUP BY basket
ORDER BY basket;
```

- `COUNT(*) FILTER (WHERE ...)` — подсчёт только строк, подходящих под условие; аналог `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`.

---

# Запрос 2

## CTE late

> Отбирает **доставленные заказы с опозданием**.

> **orders:**
> - `order_id`
> - `customer_id`
> - `order_status`
> - `order_purchase_timestamp`
> - `order_approved_at`
> - `order_delivered_carrier_date`
> - `order_delivered_customer_date`
> - `order_estimated_delivery_date`

> **late:**
> - `order_id`

```sql
WITH late AS (
    SELECT o.order_id
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date
)
```

---

## CTE late_scored

> Подтягивает к каждому заказу **оценку из последнего отзыва**.

> **late:**
> - `order_id`

> **order_reviews:**
> - `review_id`
> - `order_id`
> - `review_score`
> - `review_comment_title`
> - `review_comment_message`
> - `review_creation_date`
> - `review_answer_timestamp`

> **late_scored:**
> - `order_id`
> - `review_score`

```sql
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
)
```

- `LATERAL` — подзапрос может ссылаться на колонки внешней таблицы (`l.order_id`) и выполняется для каждой её строки.
- `ORDER BY ... LIMIT 1` внутри — последний отзыв (та же задача, что `DISTINCT ON` в запросе 1, другим способом).
- `CROSS JOIN LATERAL` отбрасывает заказы, для которых подзапрос ничего не вернул.

---

## CTE late_cat

> Привязывает к заказам **категории товаров** (английское название).

> **late_scored:**
> - `order_id`
> - `review_score`

> **order_items:**
> - `order_id`
> - `order_item_id`
> - `product_id`
> - `seller_id`
> - `shipping_limit_date`
> - `price`
> - `freight_value`

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

> **late_cat:**
> - `order_id`
> - `review_score`
> - `category`

```sql
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
```

- `LEFT JOIN` + `COALESCE` — если перевода нет, остаётся исходное название.
- `DISTINCT` — один заказ учитывается в категории один раз, даже если в нём несколько товаров этой категории.

---

## Итоговый SELECT (запрос 2)

> По каждой категории: **число опоздавших заказов и доля оценок 1–2**; топ-5 категорий.

> **late_cat:**
> - `order_id`
> - `review_score`
> - `category`

> **Результат:**
> - `category`
> - `late_orders`
> - `low_score_pct`

```sql
SELECT
    category,
    COUNT(*) AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS low_score_pct
FROM late_cat
GROUP BY category
HAVING COUNT(*) >= 100
ORDER BY low_score_pct DESC
LIMIT 5;
```

- `HAVING` фильтрует группы после `GROUP BY`: остаются категории со 100+ заказами.
