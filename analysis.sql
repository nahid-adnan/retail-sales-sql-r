-- SQLite. Input tables are populated from the two supplied CSVs by run.py.
-- Prices are integer Australian cents. Returns are attributed to the original sale month.
CREATE TEMP VIEW clean_lines AS
SELECT DISTINCT line_id, order_id, order_date, customer_id, channel, status,
       UPPER(TRIM(sku)) AS sku, qty, returned_qty
FROM raw_lines;

CREATE TEMP VIEW order_totals AS
SELECT l.order_id, l.order_date, l.customer_id, l.channel,
       SUM(l.qty * p.unit_cents) AS gross_cents,
       SUM(l.returned_qty * p.unit_cents) AS refund_cents,
       SUM((l.qty - l.returned_qty) * p.unit_cents) AS net_cents
FROM clean_lines AS l
JOIN products AS p ON p.sku = l.sku
WHERE l.status = 'paid'
GROUP BY l.order_id, l.order_date, l.customer_id, l.channel;

CREATE TEMP VIEW monthly_sales AS
WITH by_month AS (
    SELECT SUBSTR(order_date, 1, 7) AS month, COUNT(*) AS paid_orders,
           SUM(gross_cents) AS gross_cents, SUM(refund_cents) AS refund_cents,
           SUM(net_cents) AS net_cents
    FROM order_totals
    GROUP BY month
), previous AS (
    SELECT *, LAG(net_cents) OVER (ORDER BY month) AS previous_net
    FROM by_month
)
SELECT month, paid_orders, gross_cents / 100.0 AS gross_aud,
       refund_cents / 100.0 AS refunds_aud, net_cents / 100.0 AS net_aud,
       ROUND(100.0 * (net_cents - previous_net) / NULLIF(previous_net, 0), 2) AS growth_pct
FROM previous;

CREATE TEMP VIEW repeat_customers AS
WITH visits AS (
    SELECT customer_id, order_id, order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS visit_no
    FROM order_totals
), customer_months AS (
    SELECT SUBSTR(order_date, 1, 7) AS month, customer_id,
           MAX(visit_no > 1) AS made_repeat_purchase
    FROM visits GROUP BY month, customer_id
)
SELECT month, COUNT(*) AS active_customers, SUM(made_repeat_purchase) AS repeat_customers,
       ROUND(100.0 * AVG(made_repeat_purchase), 1) AS repeat_pct
FROM customer_months GROUP BY month;

CREATE TEMP VIEW category_sales AS
SELECT p.category, SUM(l.qty) AS units_sold, SUM(l.returned_qty) AS units_returned,
       ROUND(100.0 * SUM(l.returned_qty) / SUM(l.qty), 2) AS unit_return_pct,
       SUM((l.qty-l.returned_qty)*p.unit_cents)/100.0 AS net_aud
FROM clean_lines AS l JOIN products AS p ON p.sku=l.sku
WHERE l.status='paid' GROUP BY p.category;

CREATE TEMP VIEW customer_baskets AS
SELECT customer_id, channel, COUNT(*) AS paid_orders,
       SUM(net_cents) / (100.0 * COUNT(*)) AS mean_basket_aud
FROM order_totals GROUP BY customer_id, channel;
