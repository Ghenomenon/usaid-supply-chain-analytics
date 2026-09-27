-- Step 1: create the shipments table and load the cleaned CSV exported from R
DROP TABLE IF EXISTS shipments;

CREATE TABLE shipments (
  id                       INTEGER PRIMARY KEY,
  project_code             TEXT,
  country                  TEXT,
  managed_by               TEXT,
  fulfill_via              TEXT,
  vendor_inco_term         TEXT,
  shipment_mode            TEXT,
  scheduled_delivery_date  TEXT,   -- ISO date string, YYYY-MM-DD
  delivered_to_client_date TEXT,
  delivery_recorded_date   TEXT,
  delay_days               INTEGER,
  product_group            TEXT,
  sub_classification       TEXT,
  vendor                   TEXT,
  brand                    TEXT,
  line_item_quantity       INTEGER,
  line_item_value          REAL,
  pack_price               REAL,
  unit_price               REAL,
  manufacturing_site       TEXT,
  first_line_designation   TEXT,
  freight_cost_numeric     REAL    -- NULL where freight was categorical text, per R cleaning
);

.mode csv
.import --skip 1 data/shipments_clean.csv shipments

SELECT 'Row count:' AS label, COUNT(*) AS value FROM shipments;
