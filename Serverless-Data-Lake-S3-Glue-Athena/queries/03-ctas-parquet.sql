-- Convert the raw CSV table to partitioned, Snappy-compressed Parquet
CREATE TABLE orders_parquet
WITH (
  format              = 'PARQUET',
  write_compression   = 'SNAPPY',
  external_location   = 's3://BUCKET/curated/orders/',
  partitioned_by      = ARRAY['year', 'month']
) AS
SELECT order_id,
       CAST(order_ts AS timestamp) AS order_ts,
       customer_id, region, category, product,
       quantity, unit_price, payment_method, status,
       year, month
FROM   orders;
