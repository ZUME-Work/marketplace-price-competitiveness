"""Rebuild marketplace.duckdb from data/raw/ by running every sql/*.sql file in name order.

Usage: python scripts/build_db.py
"""
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "marketplace.duckdb"

if __name__ == "__main__":
    con = duckdb.connect(str(DB))
    con.execute(f"SET file_search_path = '{ROOT.as_posix()}'")
    for sql_file in sorted((ROOT / "sql").glob("*.sql")):
        print(f"-- running {sql_file.name}")
        con.execute(sql_file.read_text())
    con.close()
    print(f"Built {DB}")
