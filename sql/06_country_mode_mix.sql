.mode column
.headers on

-- Step 6: for the 5 worst-late countries, what's their shipment-mode mix?
-- (explains WHY they're late: country-specific bottleneck vs. just using slower modes more)

WITH worst5 AS (
  SELECT country
  FROM shipments
  GROUP BY country
  HAVING COUNT(*) >= 30
  ORDER BY 100.0 * SUM(CASE WHEN delay_days > 0 THEN 1 ELSE 0 END) / COUNT(*) DESC
  LIMIT 5
)
SELECT
  s.country,
  s.shipment_mode,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY s.country), 1) AS pct_of_country
FROM shipments s
JOIN worst5 w ON s.country = w.country
GROUP BY s.country, s.shipment_mode
ORDER BY s.country, n DESC;
