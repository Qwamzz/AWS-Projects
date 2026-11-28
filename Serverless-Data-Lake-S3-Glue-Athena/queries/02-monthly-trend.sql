-- Monthly revenue and average order value across all partitions
SELECT month,
       COUNT(*)                                        AS orders,
       ROUND(SUM(quantity * unit_price), 2)            AS revenue,
       ROUND(AVG(quantity * unit_price), 2)            AS avg_order_value
FROM   orders
WHERE  status = 'completed'
GROUP  BY month
ORDER  BY month;
