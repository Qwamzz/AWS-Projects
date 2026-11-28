"""Generates synthetic e-commerce orders as Hive-partitioned CSV files.

Output layout (partition folders are what Glue turns into partition columns):
  sample-data/orders/year=2026/month=01/orders.csv
  ...
"""
import csv
import os
import random
import sys
from datetime import datetime, timedelta

ROWS_PER_MONTH = int(sys.argv[1]) if len(sys.argv) > 1 else 25000
YEAR = 2026
MONTHS = range(1, 7)
OUT = os.path.join(os.path.dirname(__file__), "..", "sample-data", "orders")

REGIONS = ["us-east", "us-west", "eu-west", "eu-central", "ap-south", "ap-northeast", "sa-east"]
CATALOG = {
    "Electronics": [("Headphones", 89.0), ("Keyboard", 59.0), ("Monitor", 249.0), ("Webcam", 69.0)],
    "Books": [("Cloud Patterns", 39.0), ("Python Basics", 29.0), ("Data at Scale", 49.0)],
    "Home": [("Desk Lamp", 34.0), ("Coffee Grinder", 79.0), ("Plant Pot", 18.0)],
    "Sports": [("Yoga Mat", 25.0), ("Water Bottle", 15.0), ("Running Shoes", 119.0)],
    "Toys": [("Puzzle", 22.0), ("Building Blocks", 45.0)],
}
PAYMENTS = ["card", "card", "card", "wallet", "bank_transfer"]
STATUSES = ["completed"] * 17 + ["returned", "cancelled", "pending"]

random.seed(42)
order_id = 100000
for month in MONTHS:
    folder = os.path.join(OUT, f"year={YEAR}", f"month={month:02d}")
    os.makedirs(folder, exist_ok=True)
    start = datetime(YEAR, month, 1)
    days = ((datetime(YEAR, month + 1, 1) if month < 12 else datetime(YEAR + 1, 1, 1)) - start).days
    with open(os.path.join(folder, "orders.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["order_id", "order_ts", "customer_id", "region", "category",
                    "product", "quantity", "unit_price", "payment_method", "status"])
        for _ in range(ROWS_PER_MONTH):
            order_id += 1
            category = random.choice(list(CATALOG))
            product, price = random.choice(CATALOG[category])
            ts = start + timedelta(seconds=random.randint(0, days * 86400 - 1))
            w.writerow([order_id, ts.strftime("%Y-%m-%d %H:%M:%S"), f"C{random.randint(1, 8000):05d}",
                        random.choice(REGIONS), category, product, random.choices([1, 2, 3, 4], [70, 20, 7, 3])[0],
                        f"{price * random.uniform(0.9, 1.1):.2f}", random.choice(PAYMENTS), random.choice(STATUSES)])
print("Generated", len(MONTHS) * ROWS_PER_MONTH, "orders in", os.path.abspath(OUT))
