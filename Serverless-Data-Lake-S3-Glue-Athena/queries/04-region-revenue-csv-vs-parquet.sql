-- Same question against both tables. Compare "Data scanned" in Athena.
SELECT region, ROUND(SUM(quantity * unit_price), 2) AS revenue
FROM   orders            -- CSV
WHERE  status = 'completed'
GROUP  BY region ORDER BY revenue DESC;

SELECT region, ROUND(SUM(quantity * unit_price), 2) AS revenue
FROM   orders_parquet    -- Parquet
WHERE  status = 'completed'
GROUP  BY region ORDER BY revenue DESC;
