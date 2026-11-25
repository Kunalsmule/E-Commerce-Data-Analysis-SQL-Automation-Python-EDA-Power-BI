-- Analyse monthly order, sales, freight and payment performance.
WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_sales,
        SUM(freight_value) AS freight_value
    FROM curated.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value
    FROM curated.order_payments
    GROUP BY order_id
)
SELECT
    YEAR(o.order_purchase_timestamp) AS sales_year,
    MONTH(o.order_purchase_timestamp) AS sales_month,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END) AS delivered_orders,
    SUM(CASE WHEN o.order_status = 'delivered' THEN COALESCE(i.merchandise_sales, 0) ELSE 0 END) AS merchandise_sales,
    SUM(CASE WHEN o.order_status = 'delivered' THEN COALESCE(i.freight_value, 0) ELSE 0 END) AS freight_revenue,
    SUM(CASE WHEN o.order_status = 'delivered' THEN COALESCE(p.payment_value, 0) ELSE 0 END) AS payment_value
FROM curated.orders o
LEFT JOIN item_totals i
    ON o.order_id = i.order_id
LEFT JOIN payment_totals p
    ON o.order_id = p.order_id
GROUP BY
    YEAR(o.order_purchase_timestamp),
    MONTH(o.order_purchase_timestamp)
ORDER BY
    sales_year,
    sales_month;


    -- Rank product categories by delivered merchandise sales.
WITH category_sales AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name) AS category,
        COUNT(DISTINCT oi.order_id) AS total_orders,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS merchandise_sales,
        SUM(oi.freight_value) AS freight_value,
        AVG(oi.price) AS average_item_price
    FROM curated.order_items oi
    JOIN curated.orders o
        ON oi.order_id = o.order_id
    JOIN curated.products p
        ON oi.product_id = p.product_id
    LEFT JOIN curated.category_translation t
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY
        COALESCE(t.product_category_name_english, p.product_category_name)
)
SELECT
    DENSE_RANK() OVER (ORDER BY merchandise_sales DESC) AS sales_rank,
    category,
    total_orders,
    items_sold,
    merchandise_sales,
    freight_value,
    average_item_price
FROM category_sales
ORDER BY merchandise_sales DESC;

-- Which sellers generate the highest merchandise sales?
SELECT TOP 20
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(*) AS items_sold,
    SUM(oi.price) AS merchandise_sales,
    SUM(oi.freight_value) AS freight_value,
    AVG(oi.price) AS average_item_price
FROM curated.order_items oi
JOIN curated.orders o
    ON oi.order_id = o.order_id
JOIN curated.sellers s
    ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
GROUP BY
    s.seller_id,
    s.seller_city,
    s.seller_state
ORDER BY merchandise_sales DESC;


-- Which sellers have the highest average delivery delays and late order rates?
WITH seller_orders AS (
    SELECT DISTINCT
        oi.seller_id,
        oi.order_id,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM curated.order_items oi
    JOIN curated.orders o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT TOP 20
    so.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(*) AS delivered_orders,
    AVG(CAST(DATEDIFF(DAY, so.order_estimated_delivery_date, so.order_delivered_customer_date) AS DECIMAL(10,2))) AS average_delay_days,
    SUM(CASE
        WHEN so.order_delivered_customer_date > so.order_estimated_delivery_date
        THEN 1 ELSE 0
    END) AS late_orders,
    CAST(100.0 * SUM(CASE
        WHEN so.order_delivered_customer_date > so.order_estimated_delivery_date
        THEN 1 ELSE 0
    END) / COUNT(*) AS DECIMAL(5,2)) AS late_order_rate
FROM seller_orders so
JOIN curated.sellers s
    ON so.seller_id = s.seller_id
GROUP BY so.seller_id, s.seller_city, s.seller_state
HAVING COUNT(*) >= 30
ORDER BY average_delay_days DESC;


-- Which product categories have the lowest average customer review scores?
SELECT
    COALESCE(t.product_category_name_english, 'Unknown') AS product_category,
    COUNT(DISTINCT r.review_record_key) AS review_count,
    CAST(AVG(CAST(r.review_score AS DECIMAL(10,2))) AS DECIMAL(4,2)) AS average_review_score,
    SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS low_score_reviews
FROM curated.order_reviews r
JOIN curated.order_items oi
    ON r.order_id = oi.order_id
JOIN curated.products p
    ON oi.product_id = p.product_id
LEFT JOIN curated.category_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY COALESCE(t.product_category_name_english, 'Unknown')
HAVING COUNT(DISTINCT r.review_record_key) >= 30
ORDER BY average_review_score ASC;


-- Are late deliveries associated with lower customer review scores?
SELECT
    d.delivery_status,
    COUNT(DISTINCT r.review_record_key) AS review_count,
    CAST(AVG(CAST(r.review_score AS DECIMAL(10,2))) AS DECIMAL(4,2)) AS average_review_score,
    SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS low_score_reviews
FROM curated.vw_delivery_performance d
JOIN curated.order_reviews r
    ON d.order_id = r.order_id
GROUP BY d.delivery_status
ORDER BY average_review_score;


-- Which payment methods generate the highest payment value and order volume?
SELECT
    payment_type,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(*) AS payment_records,
    SUM(payment_value) AS total_payment_value,
    AVG(payment_value) AS average_payment_value,
    AVG(CAST(payment_installments AS DECIMAL(10,2))) AS average_installments
FROM curated.order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;


-- Which Brazilian states generate the highest delivered merchandise sales?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    SUM(oi.price) AS merchandise_sales,
    SUM(oi.freight_value) AS freight_value,
    CAST(SUM(oi.price) / COUNT(DISTINCT o.order_id) AS DECIMAL(12,2)) AS average_order_value
FROM curated.orders o
JOIN curated.customers c
    ON o.customer_id = c.customer_id
JOIN curated.order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY merchandise_sales DESC;


-- Which Brazilian states have the longest average delivery delays?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    AVG(CAST(DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) AS DECIMAL(10,2))) AS average_delay_days,
    SUM(CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 1 ELSE 0
    END) AS late_orders,
    CAST(100.0 * SUM(CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 1 ELSE 0
    END) / COUNT(*) AS DECIMAL(5,2)) AS late_order_rate
FROM curated.orders o
JOIN curated.customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY average_delay_days DESC;

-- How many orders have payment values that differ from merchandise sales plus freight?
WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_sales,
        SUM(freight_value) AS freight
    FROM curated.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS total_payment
    FROM curated.order_payments
    GROUP BY order_id
),
reconciliation AS (
    SELECT
        o.order_id,
        i.merchandise_sales,
        i.freight,
        p.total_payment,
        CASE
            WHEN i.order_id IS NULL THEN 'Missing Items'
            WHEN p.order_id IS NULL THEN 'Missing Payment'
            WHEN ABS(p.total_payment - i.merchandise_sales - i.freight) <= 0.01
                THEN 'Reconciled'
            WHEN p.total_payment > i.merchandise_sales + i.freight
                THEN 'Payment Above Items and Freight'
            ELSE 'Payment Below Items and Freight'
        END AS reconciliation_status
    FROM curated.orders o
    LEFT JOIN item_totals i ON o.order_id = i.order_id
    LEFT JOIN payment_totals p ON o.order_id = p.order_id
)
SELECT
    reconciliation_status,
    COUNT(*) AS order_count,
    CAST(SUM(COALESCE(total_payment, 0)) AS DECIMAL(18,2)) AS total_payment_value
FROM reconciliation
GROUP BY reconciliation_status
ORDER BY order_count DESC;


-- How much of delivered merchandise sales is generated by the top 10% of sellers?
WITH seller_sales AS (
    SELECT
        seller_id,
        SUM(price) AS merchandise_sales
    FROM curated.order_items
    WHERE order_id IN (
        SELECT order_id
        FROM curated.orders
        WHERE order_status = 'delivered'
    )
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        seller_id,
        merchandise_sales,
        ROW_NUMBER() OVER (ORDER BY merchandise_sales DESC) AS seller_rank,
        COUNT(*) OVER () AS total_sellers
    FROM seller_sales
)
SELECT
    COUNT(*) AS top_seller_count,
    CAST(SUM(merchandise_sales) AS DECIMAL(18,2)) AS top_seller_sales,
    CAST(100.0 * SUM(merchandise_sales) /
        (SELECT SUM(merchandise_sales) FROM seller_sales) AS DECIMAL(5,2)) AS sales_share_pct
FROM ranked_sellers
WHERE seller_rank <= CEILING(total_sellers * 0.10);


-- Which product pairs most frequently appear in the same delivered order?
SELECT TOP 20
    a.product_id AS product_1,
    b.product_id AS product_2,
    COUNT(DISTINCT a.order_id) AS orders_together
FROM curated.order_items a
JOIN curated.order_items b
    ON a.order_id = b.order_id
    AND a.product_id < b.product_id
JOIN curated.orders o
    ON a.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY a.product_id, b.product_id
ORDER BY orders_together DESC;

-- What are the product names and categories of the most frequently purchased product pairs?
WITH product_pairs AS (
    SELECT TOP 10
        a.product_id AS product_1,
        b.product_id AS product_2,
        COUNT(DISTINCT a.order_id) AS orders_together
    FROM curated.order_items a
    JOIN curated.order_items b
        ON a.order_id = b.order_id
        AND a.product_id < b.product_id
    JOIN curated.orders o
        ON a.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY a.product_id, b.product_id
    ORDER BY orders_together DESC
)
SELECT
    pp.orders_together,
    pp.product_1,
    p1.product_category_name AS category_1,
    pp.product_2,
    p2.product_category_name AS category_2
FROM product_pairs pp
LEFT JOIN curated.products p1 ON pp.product_1 = p1.product_id
LEFT JOIN curated.products p2 ON pp.product_2 = p2.product_id
ORDER BY pp.orders_together DESC;

-- How do monthly delivered order volume and average order value change over time?
SELECT
    FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS order_month,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    CAST(SUM(i.merchandise_sales) AS DECIMAL(18,2)) AS merchandise_sales,
    CAST(
        SUM(i.merchandise_sales) / COUNT(DISTINCT o.order_id)
        AS DECIMAL(18,2)
    ) AS average_order_value
FROM curated.orders o
JOIN (
    SELECT
        order_id,
        SUM(price) AS merchandise_sales
    FROM curated.order_items
    GROUP BY order_id
) i ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
GROUP BY FORMAT(o.order_purchase_timestamp, 'yyyy-MM')
ORDER BY order_month;


-- How many customers placed one delivered order versus multiple delivered orders?
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS delivered_orders
    FROM curated.vw_order_summary
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN delivered_orders = 1 THEN 'One-time Customer'
        ELSE 'Repeat Customer'
    END AS customer_type,
    COUNT(*) AS customer_count,
    CAST(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
        AS DECIMAL(5,2)
    ) AS customer_percentage
FROM customer_orders
GROUP BY
    CASE
        WHEN delivered_orders = 1 THEN 'One-time Customer'
        ELSE 'Repeat Customer'
    END
ORDER BY customer_count DESC;


-- How many days does it take repeat customers to place their second delivered order?
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS purchase_number
    FROM curated.vw_order_summary
    WHERE order_status = 'delivered'
),
repeat_customers AS (
    SELECT
        customer_unique_id,
        MAX(CASE WHEN purchase_number = 1 THEN order_purchase_timestamp END) AS first_order_date,
        MAX(CASE WHEN purchase_number = 2 THEN order_purchase_timestamp END) AS second_order_date
    FROM customer_orders
    GROUP BY customer_unique_id
    HAVING COUNT(*) >= 2
)
SELECT
    COUNT(*) AS repeat_customers,
    CAST(AVG(CAST(DATEDIFF(DAY, first_order_date, second_order_date) AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS average_days_to_second_order,
    MIN(DATEDIFF(DAY, first_order_date, second_order_date)) AS minimum_days,
    MAX(DATEDIFF(DAY, first_order_date, second_order_date)) AS maximum_days
FROM repeat_customers;


-- What percentage of eligible customers place another delivered order within 7, 30 or 90 days?
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS purchase_number
    FROM curated.vw_order_summary
    WHERE order_status = 'delivered'
),
first_orders AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp AS first_order_date
    FROM customer_orders
    WHERE purchase_number = 1
),
repeat_orders AS (
    SELECT
        customer_unique_id,
        MIN(order_purchase_timestamp) AS second_order_date
    FROM customer_orders
    WHERE purchase_number > 1
    GROUP BY customer_unique_id
),
eligible_customers AS (
    SELECT
        f.customer_unique_id,
        f.first_order_date,
        r.second_order_date
    FROM first_orders f
    LEFT JOIN repeat_orders r
        ON f.customer_unique_id = r.customer_unique_id
    WHERE f.first_order_date <= DATEADD(
    DAY, -90,
    (SELECT MAX(order_purchase_timestamp) FROM curated.orders)

    )
)
SELECT
    COUNT(*) AS eligible_customers,
    SUM(CASE WHEN second_order_date <= DATEADD(DAY, 7, first_order_date) THEN 1 ELSE 0 END) AS repeat_within_7_days,
    SUM(CASE WHEN second_order_date <= DATEADD(DAY, 30, first_order_date) THEN 1 ELSE 0 END) AS repeat_within_30_days,
    SUM(CASE WHEN second_order_date <= DATEADD(DAY, 90, first_order_date) THEN 1 ELSE 0 END) AS repeat_within_90_days
FROM eligible_customers;

-- Which first purchase month cohorts have the highest repeat customer rates?
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS purchase_number
    FROM curated.vw_order_summary
    WHERE order_status = 'delivered'
),
customer_cohorts AS (
    SELECT
        customer_unique_id,
        MIN(order_purchase_timestamp) AS first_order_date,
        COUNT(*) AS delivered_orders
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    FORMAT(first_order_date, 'yyyy-MM') AS cohort_month,
    COUNT(*) AS customers,
    SUM(CASE WHEN delivered_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    CAST(
        100.0 * SUM(CASE WHEN delivered_orders > 1 THEN 1 ELSE 0 END)
        / COUNT(*) AS DECIMAL(5,2)
    ) AS repeat_customer_rate
FROM customer_cohorts
GROUP BY FORMAT(first_order_date, 'yyyy-MM')
ORDER BY cohort_month;

-- What percentage of each monthly customer cohort makes another delivered purchase in subsequent months?
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS purchase_number
    FROM curated.vw_order_summary
    WHERE order_status = 'delivered'
),
first_orders AS (
    SELECT
        customer_unique_id,
        MIN(order_purchase_timestamp) AS first_order_date
    FROM customer_orders
    GROUP BY customer_unique_id
),
cohort_activity AS (
    SELECT DISTINCT
        f.customer_unique_id,
        DATEFROMPARTS(YEAR(f.first_order_date), MONTH(f.first_order_date), 1) AS cohort_month,
        DATEDIFF(
            MONTH,
            DATEFROMPARTS(YEAR(f.first_order_date), MONTH(f.first_order_date), 1),
            DATEFROMPARTS(YEAR(c.order_purchase_timestamp), MONTH(c.order_purchase_timestamp), 1)
        ) AS month_number
    FROM first_orders f
    JOIN customer_orders c
        ON f.customer_unique_id = c.customer_unique_id
)
SELECT
    cohort_month,
    month_number,
    COUNT(*) AS active_customers
FROM cohort_activity
GROUP BY cohort_month, month_number
ORDER BY cohort_month, month_number;


-- What percentage of each customer cohort makes a delivered purchase in each subsequent calendar month?
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS purchase_number
    FROM curated.vw_order_summary
    WHERE order_status = 'delivered'
),
first_orders AS (
    SELECT
        customer_unique_id,
        MIN(order_purchase_timestamp) AS first_order_date
    FROM customer_orders
    GROUP BY customer_unique_id
),
cohort_activity AS (
    SELECT DISTINCT
        f.customer_unique_id,
        DATEFROMPARTS(YEAR(f.first_order_date), MONTH(f.first_order_date), 1) AS cohort_month,
        DATEDIFF(
            MONTH,
            DATEFROMPARTS(YEAR(f.first_order_date), MONTH(f.first_order_date), 1),
            DATEFROMPARTS(YEAR(c.order_purchase_timestamp), MONTH(c.order_purchase_timestamp), 1)
        ) AS month_number
    FROM first_orders f
    JOIN customer_orders c
        ON f.customer_unique_id = c.customer_unique_id
),
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM cohort_activity
    WHERE month_number = 0
    GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    a.month_number,
    s.cohort_size,
    COUNT(*) AS active_customers,
    CAST(
        100.0 * COUNT(*) / s.cohort_size
        AS DECIMAL(5,2)
    ) AS retention_rate
FROM cohort_activity a
JOIN cohort_sizes s
    ON a.cohort_month = s.cohort_month
GROUP BY
    a.cohort_month,
    a.month_number,
    s.cohort_size
ORDER BY a.cohort_month, a.month_number;

-- Which customers generate the highest historical delivered merchandise value?
SELECT TOP 20
    customer_unique_id,
    total_orders,
    CAST(historical_merchandise_value AS DECIMAL(18,2)) AS historical_merchandise_value,
    CAST(
        historical_merchandise_value / NULLIF(total_orders, 0)
        AS DECIMAL(18,2)
    ) AS average_order_value
FROM curated.vw_customer_summary
WHERE total_orders > 0
ORDER BY historical_merchandise_value DESC;

-- How many customers have been inactive for 90 days or longer?
WITH customer_inactivity AS (
    SELECT
        customer_unique_id,
        total_orders,
        DATEDIFF(
            DAY,
            last_purchase_date,
            (SELECT MAX(last_purchase_date)
             FROM curated.vw_customer_summary)
        ) AS days_inactive
    FROM curated.vw_customer_summary
    WHERE last_purchase_date IS NOT NULL
)
SELECT
    CASE
        WHEN days_inactive < 30 THEN 'Under 30 days'
        WHEN days_inactive < 60 THEN '30-59 days'
        WHEN days_inactive < 90 THEN '60-89 days'
        ELSE '90+ days'
    END AS inactivity_group,
    COUNT(*) AS customer_count
FROM customer_inactivity
GROUP BY
    CASE
        WHEN days_inactive < 30 THEN 'Under 30 days'
        WHEN days_inactive < 60 THEN '30-59 days'
        WHEN days_inactive < 90 THEN '60-89 days'
        ELSE '90+ days'
    END
ORDER BY MIN(days_inactive);


-- Which customer purchase groups have the highest 90 day inactivity?
WITH customer_activity AS (
    SELECT
        customer_unique_id,
        total_orders,
        DATEDIFF(
            DAY,
            last_purchase_date,
            (SELECT MAX(last_purchase_date)
             FROM curated.vw_customer_summary)
        ) AS days_inactive
    FROM curated.vw_customer_summary
    WHERE last_purchase_date IS NOT NULL
)
SELECT
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_segment,
    COUNT(*) AS customer_count,
    SUM(CASE WHEN days_inactive >= 90 THEN 1 ELSE 0 END) AS inactive_90_days,
    CAST(
        100.0 * SUM(CASE WHEN days_inactive >= 90 THEN 1 ELSE 0 END)
        / COUNT(*) AS DECIMAL(5,2)
    ) AS inactivity_rate
FROM customer_activity
GROUP BY
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END;


    -- How does historical merchandise value differ between one time and repeat customers?
SELECT
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_segment,
    COUNT(*) AS customer_count,
    CAST(AVG(historical_merchandise_value) AS DECIMAL(18,2)) AS avg_historical_value,
    CAST(AVG(total_orders * 1.0) AS DECIMAL(10,2)) AS avg_orders,
    CAST(SUM(historical_merchandise_value) AS DECIMAL(18,2)) AS total_merchandise_value
FROM curated.vw_customer_summary
GROUP BY
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END;

    -- Which products generate the highest delivered merchandise sales?
SELECT TOP 20
    p.product_id,
    COALESCE(t.product_category_name_english, 'Unknown') AS category,
    COUNT(DISTINCT oi.order_id) AS delivered_orders,
    SUM(oi.order_item_id * 0 + 1) AS items_sold,
    CAST(SUM(oi.price) AS DECIMAL(18,2)) AS merchandise_sales
FROM curated.order_items oi
JOIN curated.orders o
    ON oi.order_id = o.order_id
JOIN curated.products p
    ON oi.product_id = p.product_id
LEFT JOIN curated.category_translation t
    ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY
    p.product_id,
    COALESCE(t.product_category_name_english, 'Unknown')
ORDER BY merchandise_sales DESC;


-- What percentage of delivered merchandise sales comes from each product category?
WITH category_sales AS (
    SELECT
        COALESCE(t.product_category_name_english, 'Unknown') AS category,
        SUM(oi.price) AS merchandise_sales
    FROM curated.order_items oi
    JOIN curated.orders o
        ON oi.order_id = o.order_id
    JOIN curated.products p
        ON oi.product_id = p.product_id
    LEFT JOIN curated.category_translation t
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY COALESCE(t.product_category_name_english, 'Unknown')
)
SELECT
    category,
    CAST(merchandise_sales AS DECIMAL(18,2)) AS merchandise_sales,
    CAST(
        100.0 * merchandise_sales / SUM(merchandise_sales) OVER()
        AS DECIMAL(6,2)
    ) AS sales_percentage,
    CAST(
        100.0 * SUM(merchandise_sales) OVER (
            ORDER BY merchandise_sales DESC
            ROWS UNBOUNDED PRECEDING
        ) / SUM(merchandise_sales) OVER()
        AS DECIMAL(6,2)
    ) AS cumulative_sales_percentage
FROM category_sales
ORDER BY merchandise_sales DESC;


-- Which sellers fulfil the highest number of delivered orders?
SELECT TOP 20
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS delivered_orders
FROM curated.order_items oi
JOIN curated.orders o
    ON oi.order_id = o.order_id
JOIN curated.sellers s
    ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
GROUP BY
    s.seller_id,
    s.seller_city,
    s.seller_state
ORDER BY delivered_orders DESC;

-- Which sellers receive the lowest average review scores on delivered orders?
WITH seller_orders AS (
    SELECT DISTINCT
        oi.seller_id,
        oi.order_id
    FROM curated.order_items oi
    JOIN curated.orders o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
)
SELECT TOP 20
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(*) AS reviewed_orders,
    CAST(AVG(CAST(r.average_review_score AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS average_review_score
FROM seller_orders so
JOIN curated.sellers s
    ON so.seller_id = s.seller_id
JOIN curated.vw_review_summary r
    ON so.order_id = r.order_id
WHERE r.average_review_score IS NOT NULL
GROUP BY
    s.seller_id,
    s.seller_city,
    s.seller_state
ORDER BY average_review_score ASC, reviewed_orders DESC;


-- Are the highest selling sellers also delivering orders on time and receiving good review scores?

WITH seller_orders AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        SUM(oi.price) AS merchandise_sales
    FROM curated.order_items oi
    JOIN curated.orders o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        oi.seller_id,
        oi.order_id
)
SELECT TOP 20
    so.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(*) AS delivered_orders,
    CAST(SUM(so.merchandise_sales) AS DECIMAL(18,2)) AS merchandise_sales,
    CAST(AVG(dp.delivery_delay_days) AS DECIMAL(10,2)) AS avg_delivery_delay_days,
    COUNT(CASE WHEN dp.delivery_status = 'Late' THEN 1 END) AS late_orders,
    COUNT(rs.average_review_score) AS reviewed_orders,
    CAST(AVG(rs.average_review_score) AS DECIMAL(10,2)) AS avg_review_score
FROM seller_orders so
JOIN curated.sellers s
    ON so.seller_id = s.seller_id
LEFT JOIN curated.vw_delivery_performance dp
    ON so.order_id = dp.order_id
LEFT JOIN curated.vw_review_summary rs
    ON so.order_id = rs.order_id
GROUP BY
    so.seller_id,
    s.seller_city,
    s.seller_state
ORDER BY merchandise_sales DESC;


-- What is the average delivery time for delivered orders?
SELECT
    COUNT(delivery_days) AS orders_with_delivery_dates,
    CAST(AVG(delivery_days) AS DECIMAL(10,2)) AS avg_delivery_days
FROM curated.vw_delivery_performance;


-- What percentage of delivered orders arrive on or before the estimated delivery date?
SELECT
    COUNT(*) AS total_delivered_orders,
    COUNT(CASE WHEN delivery_status = 'On Time' THEN 1 END) AS on_time_orders,
    CAST(
        100.0 * COUNT(CASE WHEN delivery_status = 'On Time' THEN 1 END)
        / COUNT(*) AS DECIMAL(10,2)
    ) AS on_time_delivery_rate
FROM curated.vw_delivery_performance;


-- Which customer cities experience the longest average delivery delays?
SELECT
    c.customer_city,
    c.customer_state,
    COUNT(*) AS delivered_orders,
    CAST(AVG(dp.delivery_delay_days) AS DECIMAL(10,2)) AS avg_delay_days,
    COUNT(CASE WHEN dp.delivery_status = 'Late' THEN 1 END) AS late_orders,
    CAST(
        100.0 * COUNT(CASE WHEN dp.delivery_status = 'Late' THEN 1 END)
        / COUNT(*) AS DECIMAL(10,2)
    ) AS late_order_rate
FROM curated.vw_delivery_performance dp
JOIN curated.orders o
    ON dp.order_id = o.order_id
JOIN curated.customers c
    ON o.customer_id = c.customer_id
GROUP BY
    c.customer_city,
    c.customer_state
HAVING COUNT(*) >= 30
ORDER BY avg_delay_days DESC;


-- Which orders have the largest differences between payment value and merchandise plus freight?
WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_value,
        SUM(freight_value) AS freight_value
    FROM curated.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value
    FROM curated.order_payments
    GROUP BY order_id
)
SELECT TOP 20
    COALESCE(i.order_id, p.order_id) AS order_id,
    CAST(COALESCE(i.merchandise_value, 0) AS DECIMAL(18,2)) AS merchandise_value,
    CAST(COALESCE(i.freight_value, 0) AS DECIMAL(18,2)) AS freight_value,
    CAST(COALESCE(p.payment_value, 0) AS DECIMAL(18,2)) AS payment_value,
    CAST(
        COALESCE(p.payment_value, 0)
        - COALESCE(i.merchandise_value, 0)
        - COALESCE(i.freight_value, 0)
        AS DECIMAL(18,2)
    ) AS financial_difference
FROM item_totals i
FULL OUTER JOIN payment_totals p
    ON i.order_id = p.order_id
ORDER BY ABS(
    COALESCE(p.payment_value, 0)
    - COALESCE(i.merchandise_value, 0)
    - COALESCE(i.freight_value, 0)
) DESC;


-- Which orders have the largest differences between payment value and merchandise plus freight?
WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_value,
        SUM(freight_value) AS freight_value
    FROM curated.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value
    FROM curated.order_payments
    GROUP BY order_id
)
SELECT TOP 20
    COALESCE(i.order_id, p.order_id) AS order_id,
    CAST(COALESCE(i.merchandise_value, 0) AS DECIMAL(18,2)) AS merchandise_value,
    CAST(COALESCE(i.freight_value, 0) AS DECIMAL(18,2)) AS freight_value,
    CAST(COALESCE(p.payment_value, 0) AS DECIMAL(18,2)) AS payment_value,
    CAST(
        COALESCE(p.payment_value, 0)
        - COALESCE(i.merchandise_value, 0)
        - COALESCE(i.freight_value, 0)
        AS DECIMAL(18,2)
    ) AS financial_difference
FROM item_totals i
FULL OUTER JOIN payment_totals p
    ON i.order_id = p.order_id
ORDER BY ABS(
    COALESCE(p.payment_value, 0)
    - COALESCE(i.merchandise_value, 0)
    - COALESCE(i.freight_value, 0)
) DESC;


-- Which Brazilian regions have the highest average freight cost per delivered order?
WITH order_freight AS (
    SELECT
        order_id,
        SUM(freight_value) AS total_freight
    FROM curated.order_items
    GROUP BY order_id
)
SELECT
    CASE
        WHEN c.customer_state IN ('SP', 'RJ', 'MG', 'ES') THEN 'Southeast'
        WHEN c.customer_state IN ('PR', 'SC', 'RS') THEN 'South'
        WHEN c.customer_state IN ('DF', 'GO', 'MT', 'MS') THEN 'Central-West'
        WHEN c.customer_state IN ('BA', 'SE', 'AL', 'PE', 'PB', 'RN', 'CE', 'PI', 'MA') THEN 'Northeast'
        WHEN c.customer_state IN ('AC', 'AP', 'AM', 'PA', 'RO', 'RR', 'TO') THEN 'North'
        ELSE 'Unknown'
    END AS region,
    COUNT(*) AS delivered_orders,
    CAST(SUM(ofr.total_freight) AS DECIMAL(18,2)) AS total_freight,
    CAST(AVG(ofr.total_freight) AS DECIMAL(10,2)) AS avg_freight_per_order
FROM order_freight ofr
JOIN curated.orders o
    ON ofr.order_id = o.order_id
JOIN curated.customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY
    CASE
        WHEN c.customer_state IN ('SP', 'RJ', 'MG', 'ES') THEN 'Southeast'
        WHEN c.customer_state IN ('PR', 'SC', 'RS') THEN 'South'
        WHEN c.customer_state IN ('DF', 'GO', 'MT', 'MS') THEN 'Central-West'
        WHEN c.customer_state IN ('BA', 'SE', 'AL', 'PE', 'PB', 'RN', 'CE', 'PI', 'MA') THEN 'Northeast'
        WHEN c.customer_state IN ('AC', 'AP', 'AM', 'PA', 'RO', 'RR', 'TO') THEN 'North'
        ELSE 'Unknown'
    END
ORDER BY avg_freight_per_order DESC;


-- Which Brazilian states show potential business opportunities based on sales, customers, order value and delivery performance?
WITH order_metrics AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_sales,
        SUM(freight_value) AS freight_value
    FROM curated.order_items
    GROUP BY order_id
)
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    CAST(SUM(om.merchandise_sales) AS DECIMAL(18,2)) AS merchandise_sales,
    CAST(AVG(om.merchandise_sales) AS DECIMAL(10,2)) AS avg_order_value,
    CAST(AVG(om.freight_value) AS DECIMAL(10,2)) AS avg_freight,
    CAST(
        100.0 * COUNT(CASE WHEN dp.delivery_status = 'Late' THEN 1 END)
        / COUNT(*) AS DECIMAL(10,2)
    ) AS late_delivery_rate
FROM curated.orders o
JOIN curated.customers c
    ON o.customer_id = c.customer_id
JOIN order_metrics om
    ON o.order_id = om.order_id
JOIN curated.vw_delivery_performance dp
    ON o.order_id = dp.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY merchandise_sales DESC;


-- How does historical merchandise value vary with customer purchase frequency?
SELECT
    CASE
        WHEN total_orders = 1 THEN '1 order'
        WHEN total_orders = 2 THEN '2 orders'
        ELSE '3 or more orders'
    END AS purchase_frequency,
    COUNT(*) AS customer_count,
    CAST(AVG(historical_merchandise_value) AS DECIMAL(18,2)) AS avg_historical_value,
    CAST(SUM(historical_merchandise_value) AS DECIMAL(18,2)) AS total_historical_value,
    CAST(AVG(total_orders * 1.0) AS DECIMAL(10,2)) AS avg_orders_per_customer
FROM curated.vw_customer_summary
GROUP BY
    CASE
        WHEN total_orders = 1 THEN '1 order'
        WHEN total_orders = 2 THEN '2 orders'
        ELSE '3 or more orders'
    END
ORDER BY avg_historical_value DESC;


-- How does customer review experience differ between one time and repeat purchasers?
WITH customer_reviews AS (
    SELECT
        o.customer_id,
        AVG(CAST(r.review_score AS DECIMAL(10,2))) AS avg_review_score
    FROM curated.orders o
    JOIN curated.order_reviews r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.customer_id
)
SELECT
    CASE
        WHEN cs.total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_segment,
    COUNT(*) AS customer_count,
    CAST(AVG(cr.avg_review_score) AS DECIMAL(10,2)) AS avg_review_score
FROM curated.vw_customer_summary cs
JOIN curated.customers c
    ON cs.customer_unique_id = c.customer_unique_id
JOIN customer_reviews cr
    ON c.customer_id = cr.customer_id
GROUP BY
    CASE
        WHEN cs.total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END;


    -- What percentage of delivered merchandise sales comes from the top 10% of customers and products?
WITH customer_sales AS (
    SELECT
        customer_unique_id AS entity_id,
        historical_merchandise_value AS sales
    FROM curated.vw_customer_summary
),
ranked_customers AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY sales DESC) AS sales_decile
    FROM customer_sales
),
product_sales AS (
    SELECT
        product_id AS entity_id,
        SUM(price) AS sales
    FROM curated.order_items oi
    JOIN curated.orders o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY product_id
),
ranked_products AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY sales DESC) AS sales_decile
    FROM product_sales
)
SELECT
    'Customers' AS entity_type,
    COUNT(*) AS total_entities,
    SUM(CASE WHEN sales_decile = 1 THEN 1 ELSE 0 END) AS top_10_percent_entities,
    CAST(SUM(CASE WHEN sales_decile = 1 THEN sales ELSE 0 END) AS DECIMAL(18,2)) AS top_10_percent_sales,
    CAST(SUM(sales) AS DECIMAL(18,2)) AS total_sales,
    CAST(
        100.0 * SUM(CASE WHEN sales_decile = 1 THEN sales ELSE 0 END)
        / SUM(sales) AS DECIMAL(10,2)
    ) AS top_10_percent_sales_share
FROM ranked_customers

UNION ALL

SELECT
    'Products',
    COUNT(*),
    SUM(CASE WHEN sales_decile = 1 THEN 1 ELSE 0 END),
    CAST(SUM(CASE WHEN sales_decile = 1 THEN sales ELSE 0 END) AS DECIMAL(18,2)),
    CAST(SUM(sales) AS DECIMAL(18,2)),
    CAST(
        100.0 * SUM(CASE WHEN sales_decile = 1 THEN sales ELSE 0 END)
        / SUM(sales) AS DECIMAL(10,2)
    )
FROM ranked_products;

--Temporary table analysis

-- How do delivered orders compare by monthly merchandise sales and average order value?
DROP TABLE IF EXISTS #MonthlyPerformance;

WITH order_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_sales
    FROM curated.order_items
    GROUP BY order_id
)
SELECT
    YEAR(o.order_purchase_timestamp) AS order_year,
    MONTH(o.order_purchase_timestamp) AS order_month,
    COUNT(*) AS delivered_orders,
    SUM(ot.merchandise_sales) AS merchandise_sales,
    AVG(ot.merchandise_sales) AS average_order_value
INTO #MonthlyPerformance
FROM curated.orders o
JOIN order_totals ot
    ON o.order_id = ot.order_id
WHERE o.order_status = 'delivered'
GROUP BY
    YEAR(o.order_purchase_timestamp),
    MONTH(o.order_purchase_timestamp);

SELECT
    order_year,
    order_month,
    delivered_orders,
    CAST(merchandise_sales AS DECIMAL(18,2)) AS merchandise_sales,
    CAST(average_order_value AS DECIMAL(18,2)) AS average_order_value
FROM #MonthlyPerformance
ORDER BY order_year, order_month;

-- Which months had the highest and lowest average order values?
SELECT TOP 5
    order_year,
    order_month,
    delivered_orders,
    merchandise_sales,
    average_order_value
FROM #MonthlyPerformance
ORDER BY average_order_value DESC;

-- How can monthly performance records be indexed for faster year and month lookups?
CREATE CLUSTERED INDEX IX_MonthlyPerformance_YearMonth
ON #MonthlyPerformance (order_year, order_month);


-- What was the monthly merchandise sales performance during 2018?
SELECT
    order_year,
    order_month,
    delivered_orders,
    CAST(merchandise_sales AS DECIMAL(18,2)) AS merchandise_sales,
    CAST(average_order_value AS DECIMAL(18,2)) AS average_order_value
FROM #MonthlyPerformance
WHERE order_year = 2018
ORDER BY order_month;

-- How many delivered orders and how much merchandise sales did each state generate?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    SUM(oi.price) AS merchandise_sales
FROM curated.orders o
JOIN curated.customers c
    ON o.customer_id = c.customer_id
JOIN curated.order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY merchandise_sales DESC;

--Performance Optimization

-- Which indexes currently exist on the curated orders table?
EXEC sp_helpindex 'curated.orders';

-- How many delivered orders and how much merchandise sales did each state generate?
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    SUM(oi.price) AS merchandise_sales
FROM curated.orders o
JOIN curated.customers c
    ON o.customer_id = c.customer_id
JOIN curated.order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY merchandise_sales DESC;

-- Which index can help SQL Server filter orders by delivery status?
CREATE NONCLUSTERED INDEX IX_orders_order_status
ON curated.orders (order_status)
INCLUDE (customer_id);

-- How much storage does the new order status index use?
EXEC sp_spaceused 'curated.orders';

-- Which indexes exist on the orders table and how much space do they use?
SELECT
    i.name AS index_name,
    i.type_desc,
    SUM(ps.used_page_count) * 8 AS size_kb
FROM sys.indexes i
JOIN sys.dm_db_partition_stats ps
    ON i.object_id = ps.object_id
    AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID('curated.orders')
GROUP BY i.name, i.type_desc
ORDER BY size_kb DESC;


--Stored Procedures and Automation

-- How have monthly delivered orders and merchandise sales changed over time?
CREATE OR ALTER PROCEDURE curated.usp_MonthlyBusinessPerformance
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        YEAR(o.order_purchase_timestamp) AS order_year,
        MONTH(o.order_purchase_timestamp) AS order_month,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        SUM(oi.price) AS merchandise_sales,
        SUM(oi.price) / COUNT(DISTINCT o.order_id) AS average_order_value
    FROM curated.orders o
    JOIN curated.order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        YEAR(o.order_purchase_timestamp),
        MONTH(o.order_purchase_timestamp)
    ORDER BY
        order_year,
        order_month;
END;


-- What are the monthly delivered order and merchandise sales results?
EXEC curated.usp_MonthlyBusinessPerformance;