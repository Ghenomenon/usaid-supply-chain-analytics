.mode column
.headers on

-- Step 2: sanity-check the load

SELECT 'Schema' AS section;
.schema shipments

SELECT 'Sample rows' AS section;
SELECT id, country, shipment_mode, scheduled_delivery_date,
       delivered_to_client_date, delay_days, freight_cost_numeric
FROM shipments
LIMIT 5;

SELECT 'Null counts on key columns' AS section;
SELECT
  SUM(CASE WHEN country IS NULL THEN 1 ELSE 0 END)              AS null_country,
  SUM(CASE WHEN shipment_mode IS NULL THEN 1 ELSE 0 END)         AS null_shipment_mode,
  SUM(CASE WHEN delay_days IS NULL THEN 1 ELSE 0 END)            AS null_delay_days,
  SUM(CASE WHEN freight_cost_numeric IS NULL THEN 1 ELSE 0 END)  AS null_freight_cost
FROM shipments;
