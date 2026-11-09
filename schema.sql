-- Toronto Municipal Licensing & Standards: Investigation Activity
-- Normalized schema (SQLite dialect; nearly identical in PostgreSQL)

PRAGMA foreign_keys = ON;

DROP VIEW  IF EXISTS v_investigation_detail;
DROP VIEW  IF EXISTS v_open_backlog;
DROP TABLE IF EXISTS deficiencies;
DROP TABLE IF EXISTS investigation_properties;
DROP TABLE IF EXISTS properties;
DROP TABLE IF EXISTS investigations;

-- One row per investigation
CREATE TABLE investigations (
    investigation_id     INTEGER PRIMARY KEY,
    investigation_no     TEXT NOT NULL,            -- e.g. '25 104876 ZON 00 IV'
    case_year            INTEGER,                  -- parsed from investigation_no
    type_code            TEXT,                     -- parsed from investigation_no (ZON, PRS, ...)
    type_raw             TEXT NOT NULL,            -- original INVESTIGATION_TYPE
    category             TEXT NOT NULL,            -- standardized (strips Notice/Order prefix)
    stage                TEXT NOT NULL,            -- Initial / Notice Issued / Order Issued
    issue_action         TEXT,                     -- text after ' / ' in ISSUE ('---' -> NULL)
    current_status       TEXT NOT NULL,
    is_closed            INTEGER NOT NULL CHECK (is_closed IN (0,1)),
    in_date              DATE,
    notice_order_date    DATE,
    next_inspection      DATE,
    expiry_date          DATE
);

-- One row per distinct street address
CREATE TABLE properties (
    property_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    property_key  TEXT NOT NULL UNIQUE,            -- normalized full address
    house         TEXT,
    street        TEXT NOT NULL,
    street_type   TEXT,
    direction     TEXT,
    is_placeholder INTEGER NOT NULL DEFAULT 0      -- 1 for non-real addresses (e.g. 'WARD 01 LOCATION', '1 IBMS WARD 24')
);

-- Bridge: an investigation can cover several addresses
CREATE TABLE investigation_properties (
    investigation_id INTEGER NOT NULL REFERENCES investigations(investigation_id),
    property_id      INTEGER NOT NULL REFERENCES properties(property_id),
    PRIMARY KEY (investigation_id, property_id)
);

-- Child records: deficiencies found during an investigation
CREATE TABLE deficiencies (
    deficiency_id    INTEGER PRIMARY KEY,
    investigation_id INTEGER NOT NULL REFERENCES investigations(investigation_id),
    location         TEXT,
    sublocation      TEXT,
    description      TEXT,
    status           TEXT NOT NULL
);

CREATE INDEX idx_inv_in_date   ON investigations(in_date);
CREATE INDEX idx_inv_category  ON investigations(category);
CREATE INDEX idx_inv_status    ON investigations(is_closed, current_status);
CREATE INDEX idx_ip_property   ON investigation_properties(property_id);
CREATE INDEX idx_def_inv       ON deficiencies(investigation_id);
CREATE INDEX idx_prop_street   ON properties(street);

-- Reporting views
CREATE VIEW v_investigation_detail AS
SELECT i.*,
       p.property_id, p.property_key, p.street,
       CAST(julianday(i.notice_order_date) - julianday(i.in_date) AS INTEGER) AS days_to_notice
FROM investigations i
JOIN investigation_properties ip USING (investigation_id)
JOIN properties p USING (property_id);

CREATE VIEW v_open_backlog AS
SELECT investigation_id, category, current_status, in_date,
       CAST(julianday('2026-11-08') - julianday(in_date) AS INTEGER) AS age_days
FROM investigations
WHERE is_closed = 0 AND in_date IS NOT NULL;
