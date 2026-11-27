import csv, io, json, os
from decimal import Decimal, InvalidOperation
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client("s3")
OUTPUT_PREFIX = os.environ.get("OUTPUT_PREFIX", "processed/")


def summarize(bucket, key):
    """Read a sales CSV (item,quantity,price) and return a summary dict."""
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
    rows = list(csv.DictReader(io.StringIO(body)))
    if not rows:
        raise ValueError(f"{key} has no data rows")

    total_qty, revenue = 0, Decimal("0")
    for i, row in enumerate(rows, start=2):  # line 1 is the header
        try:
            qty = int(row["quantity"])
            price = Decimal(row["price"])
        except (KeyError, ValueError, InvalidOperation):
            raise ValueError(f"{key} line {i}: bad row {row}")
        total_qty += qty
        revenue += qty * price

    return {
        "source": key,
        "rows": len(rows),
        "total_quantity": total_qty,
        "total_revenue": str(revenue.quantize(Decimal("0.01"))),
    }


def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            s3_event = json.loads(record["body"])
            # S3 sends a one-off s3:TestEvent when the notification is created
            for r in s3_event.get("Records", []):
                bucket = r["s3"]["bucket"]["name"]
                key = unquote_plus(r["s3"]["object"]["key"])
                summary = summarize(bucket, key)
                out_key = OUTPUT_PREFIX + os.path.basename(key).rsplit(".", 1)[0] + ".json"
                s3.put_object(Bucket=bucket, Key=out_key,
                              Body=json.dumps(summary, indent=2),
                              ContentType="application/json")
                print(json.dumps({"status": "processed", **summary, "output": out_key}))
        except Exception as e:
            print(json.dumps({"status": "failed", "messageId": record["messageId"], "error": str(e)}))
            failures.append({"itemIdentifier": record["messageId"]})

    # Only the failed messages go back to the queue (partial batch response)
    return {"batchItemFailures": failures}
