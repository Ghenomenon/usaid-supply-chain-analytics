.mode column
.headers on

-- Step 4: KPI summary by shipment mode (% late, median delay, avg freight cost)

SELECT
  shipment_mode,
  COUNT(*)                                                        AS n,
  ROUND(AVG(delay_days), 2)                                       AS mean_delay_days,
  ROUND(100.0 * SUM(CASE WHEN delay_days > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_late,
  ROUND(AVG(freight_cost_numeric), 0)                             AS avg_freight_usd
FROM shipments
GROUP BY shipment_mode
ORDER BY pct_late DESC;
