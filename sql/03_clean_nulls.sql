.mode column
.headers on

-- Step 3: readr's write_csv() encodes R's NA as the literal text "NA",
-- which .import loaded as a plain string, not SQL NULL. Fix that here.

SELECT 'Before cleaning' AS stage, COUNT(*) AS literal_na_rows
FROM shipments WHERE shipment_mode = 'NA';

UPDATE shipments SET shipment_mode = NULL WHERE shipment_mode = 'NA';

SELECT 'After cleaning' AS stage, COUNT(*) AS literal_na_rows
FROM shipments WHERE shipment_mode = 'NA';

SELECT 'True NULLs now' AS stage, COUNT(*) AS null_rows
FROM shipments WHERE shipment_mode IS NULL;

-- Same bug hit freight_cost_numeric: text 'NA' stored in a REAL-affinity
-- column doesn't error, and SQLite's loose typing counts it as a non-null
-- value contributing 0 to SUM/AVG -- silently deflating every average.
SELECT 'freight_cost_numeric stored as TEXT (before fix)' AS stage, COUNT(*) AS n
FROM shipments WHERE typeof(freight_cost_numeric) = 'text';

UPDATE shipments SET freight_cost_numeric = NULL WHERE typeof(freight_cost_numeric) = 'text';

SELECT 'freight_cost_numeric stored as TEXT (after fix)' AS stage, COUNT(*) AS n
FROM shipments WHERE typeof(freight_cost_numeric) = 'text';

SELECT 'True NULLs now' AS stage, COUNT(*) AS null_rows
FROM shipments WHERE freight_cost_numeric IS NULL;
