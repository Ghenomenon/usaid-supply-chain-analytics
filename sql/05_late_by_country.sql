.mode column
.headers on

-- Step 5: late-delivery rate by country, n >= 30 to avoid small-sample noise

SELECT
  country,
  COUNT(*)                                                        AS n,
  ROUND(100.0 * SUM(CASE WHEN delay_days > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_late
FROM shipments
GROUP BY country
HAVING COUNT(*) >= 30
ORDER BY pct_late DESC
LIMIT 10;
