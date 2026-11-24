import json, os, uuid, time, boto3
from decimal import Decimal

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=lambda o: int(o) if isinstance(o, Decimal) else str(o)),
    }


def handler(event, context):
    method = event["requestContext"]["http"]["method"]
    params = event.get("pathParameters") or {}

    if method == "POST":
        data = json.loads(event.get("body") or "{}")
        item = {"id": str(uuid.uuid4())[:8], "text": data.get("text", ""), "createdAt": int(time.time())}
        table.put_item(Item=item)
        return resp(201, item)

    if method == "GET" and "id" in params:
        item = table.get_item(Key={"id": params["id"]}).get("Item")
        return resp(200, item) if item else resp(404, {"error": "not found"})

    if method == "GET":
        return resp(200, table.scan().get("Items", []))

    if method == "DELETE" and "id" in params:
        table.delete_item(Key={"id": params["id"]})
        return resp(204, {})

    return resp(400, {"error": "unsupported"})
