"""Run the SQLite case study with Python's standard library."""
from pathlib import Path
import csv
import sqlite3

ROOT = Path(__file__).resolve().parent


def load_csv(db, file, table, width):
    with (ROOT / file).open(encoding="utf-8", newline="") as stream:
        rows = csv.reader(stream)
        next(rows)
        db.executemany(f"INSERT INTO {table} VALUES ({','.join('?' * width)})", rows)


def run():
    with sqlite3.connect(":memory:") as db:
        db.executescript("""
            CREATE TABLE products(sku TEXT PRIMARY KEY, category TEXT, unit_cents INTEGER CHECK(unit_cents > 0));
            CREATE TABLE raw_lines(line_id INTEGER, order_id INTEGER, order_date TEXT, customer_id TEXT,
                channel TEXT, status TEXT, sku TEXT, qty INTEGER, returned_qty INTEGER);
        """)
        load_csv(db, "products.csv", "products", 3)
        load_csv(db, "order_lines.csv", "raw_lines", 9)
        db.executescript((ROOT / "analysis.sql").read_text(encoding="utf-8"))
        checks = {
            "conflicting line IDs": "SELECT COUNT(*) FROM (SELECT line_id FROM clean_lines GROUP BY line_id HAVING COUNT(*) > 1)",
            "unmatched products": "SELECT COUNT(*) FROM clean_lines l LEFT JOIN products p ON l.sku=p.sku WHERE p.sku IS NULL",
            "invalid quantities": "SELECT COUNT(*) FROM clean_lines WHERE qty < 1 OR returned_qty NOT BETWEEN 0 AND qty",
            "inconsistent order headers": "SELECT COUNT(*) FROM (SELECT order_id FROM clean_lines GROUP BY order_id HAVING COUNT(DISTINCT customer_id || '/' || order_date || '/' || channel || '/' || status) > 1)",
            "unreconciled cents": "SELECT SUM(gross_cents) - SUM(refund_cents) - SUM(net_cents) FROM order_totals",
        }
        for label, query in checks.items():
            if db.execute(query).fetchone()[0] != 0:
                raise ValueError(label)
        for view, sort in [("monthly_sales","month"), ("repeat_customers","month"), ("category_sales","net_aud DESC"), ("customer_baskets","customer_id, channel")]:
            cursor = db.execute(f"SELECT * FROM {view} ORDER BY {sort}")
            with (ROOT / f"{view}.csv").open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream)
                writer.writerow([column[0] for column in cursor.description])
                writer.writerows(cursor)
        print("Checks passed. Wrote four CSV tables.")
        print(db.execute("SELECT COUNT(*), SUM(net_cents)/100.0 FROM order_totals").fetchone())


if __name__ == "__main__":
    run()
