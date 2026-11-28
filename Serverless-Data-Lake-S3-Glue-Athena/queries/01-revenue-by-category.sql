-- Revenue by category for one month (partition pruning: only month=03 is read)
SELECT category,
       COUNT(*)                                  AS orders,
       ROUND(SUM(quantity * unit_price), 2)      AS revenue
FROM   orders
WHERE  year = '2026' AND month = '03' AND status = 'completed'
GROUP  BY category
ORDER  BY revenue DESC;
