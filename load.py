"""Load the three Toronto ML&S CSVs into a normalized SQLite database.

Usage: python3 load.py <csv_dir> <db_path>
"""
import re
import sqlite3
import sys
from pathlib import Path

import pandas as pd

csv_dir, db_path = Path(sys.argv[1]), Path(sys.argv[2])
here = Path(__file__).resolve().parent

read = lambda name: pd.read_csv(csv_dir / name, dtype=str, keep_default_na=False)
inv, adr, dfc = read("Investigations.csv"), read("Addresses.csv"), read("Deficiencies.csv")

def to_date(s):
    """'Jan 15, 2025' -> '2025-01-15'; blanks and 'N/A' -> NaT."""
    return pd.to_datetime(s.str.strip(), format="%b %d, %Y", errors="coerce")

# ---- investigations ----------------------------------------------------
CATEGORY_FIXES = {
    "Prop Standards": "Property Standards",
    "Long Grass": "Long Grass and Weeds",
    "Appliance": "Appliance (Emergency)",
}
def split_type(raw):
    raw = raw.strip()
    m = re.match(r"^(Notice Issued|Order Issued)\s+(.+)$", raw)
    stage, base = (m.group(1), m.group(2)) if m else ("Initial", raw)
    return CATEGORY_FIXES.get(base, base), stage

cat_stage = inv.INVESTIGATION_TYPE.map(split_type)
parts = inv["INVESTIGATION#"].str.split()
issue_action = inv.ISSUE.str.split("/", n=1).str[1].str.strip().replace({"---": None, "": None})

i = pd.DataFrame({
    "investigation_id": inv.INVESTIGATION_ID.astype(int),
    "investigation_no": inv["INVESTIGATION#"].str.strip(),
    "case_year": 2000 + parts.str[0].astype("Int64"),
    "type_code": parts.str[2],
    "type_raw": inv.INVESTIGATION_TYPE.str.strip(),
    "category": cat_stage.str[0],
    "stage": cat_stage.str[1],
    "issue_action": issue_action,
    "current_status": inv.CURRENT_STATUS.str.strip(),
    "is_closed": (inv.CURRENT_STATUS.str.strip() == "Closed").astype(int),
    "in_date": to_date(inv.IN_DATE),
    "notice_order_date": to_date(inv.NOTICE_OR_ORDER_DATE),
    "next_inspection": to_date(inv.NEXT_INSPECTION),
    "expiry_date": to_date(inv.EXPIRY_DATE),
})
# Obvious placeholder dates (e.g. year 2100) -> NULL
i.loc[i.next_inspection > "2030-12-31", "next_inspection"] = pd.NaT
for c in ["in_date", "notice_order_date", "next_inspection", "expiry_date"]:
    i[c] = i[c].dt.strftime("%Y-%m-%d")

# ---- properties + bridge ------------------------------------------------
a = adr.copy()
for c in ["PROPHOUSE", "PROPSTREET", "PROPSTREETTYPE", "PROPSTREETDIRECTION"]:
    a[c] = a[c].str.strip().str.upper()
a["property_key"] = (a.PROPHOUSE + " " + a.PROPSTREET + " " + a.PROPSTREETTYPE + " " +
                     a.PROPSTREETDIRECTION).str.replace(r"\s+", " ", regex=True).str.strip()

props = (a.drop_duplicates("property_key")
           [["property_key", "PROPHOUSE", "PROPSTREET", "PROPSTREETTYPE", "PROPSTREETDIRECTION"]]
           .rename(columns={"PROPHOUSE": "house", "PROPSTREET": "street",
                            "PROPSTREETTYPE": "street_type", "PROPSTREETDIRECTION": "direction"})
           .replace({"": None}))
# Flag placeholder "addresses" (ward-level stand-ins, e.g. for election signs)
props["is_placeholder"] = props.property_key.str.contains(
    r"\bIBMS WARD\b|^WARD \d+ LOCATION$", regex=True).astype(int)

# ---- deficiencies -------------------------------------------------------
d = pd.DataFrame({
    "deficiency_id": dfc._id.astype(int),
    "investigation_id": dfc.INVESTIGATION_ID.astype(int),
    "location": dfc.LOCATION.str.strip().replace({"": None}),
    "sublocation": dfc.SUBLOCATION.str.strip().replace({"": None}),
    "description": dfc.TEXT.str.strip(),
    "status": dfc.STATUS.str.strip(),
})

# ---- write --------------------------------------------------------------
db_path.unlink(missing_ok=True)
con = sqlite3.connect(db_path)
con.executescript((here / "schema.sql").read_text())
i.to_sql("investigations", con, if_exists="append", index=False)
props.to_sql("properties", con, if_exists="append", index=False)

pid = pd.read_sql("SELECT property_id, property_key FROM properties", con)
bridge = (a[["INVESTIGATION_ID", "property_key"]].astype({"INVESTIGATION_ID": int})
            .drop_duplicates().merge(pid, on="property_key")
            .rename(columns={"INVESTIGATION_ID": "investigation_id"})
            [["investigation_id", "property_id"]])
bridge.to_sql("investigation_properties", con, if_exists="append", index=False)
d.to_sql("deficiencies", con, if_exists="append", index=False)
con.commit()

for t in ["investigations", "properties", "investigation_properties", "deficiencies"]:
    print(f"{t:26s}{con.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]:>9,}")
print("FK violations:", len(con.execute("PRAGMA foreign_key_check").fetchall()))
con.close()
