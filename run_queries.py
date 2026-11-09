"""Run every query in queries.sql against the database and print results.

Usage: python3 run_queries.py <db_path>
"""
import re
import sqlite3
import sys
from pathlib import Path

import pandas as pd

pd.set_option("display.width", 200, "display.max_columns", 20, "display.max_colwidth", 40)
con = sqlite3.connect(sys.argv[1])
sql = (Path(__file__).resolve().parent / "queries.sql").read_text()

for block in re.split(r"(?m)^-- (?=Q\d+:)", sql)[1:]:
    title, _, body = block.partition("\n")
    print(f"\n=== {title.strip()}")
    print(pd.read_sql(body.strip().rstrip(";"), con).to_string(index=False))
