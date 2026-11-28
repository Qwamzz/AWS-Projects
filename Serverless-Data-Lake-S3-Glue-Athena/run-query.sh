#!/usr/bin/env bash
# Runs one SQL file in Athena and prints the results plus data scanned.
set -euo pipefail
cd "$(dirname "$0")"; source .deploy.env
SQL=$(sed "s/BUCKET/$BUCKET/g" "$1")
QID=$(aws athena start-query-execution --work-group "$WORKGROUP" \
  --query-execution-context Database="$DB" --query-string "$SQL" \
  --query QueryExecutionId --output text)
while true; do
  STATE=$(aws athena get-query-execution --query-execution-id "$QID" --query QueryExecution.Status.State --output text)
  case $STATE in SUCCEEDED|FAILED|CANCELLED) break;; esac; sleep 2
done
aws athena get-query-execution --query-execution-id "$QID" \
  --query "QueryExecution.{State:Status.State,ScannedBytes:Statistics.DataScannedInBytes,Ms:Statistics.TotalExecutionTimeInMillis}"
[ "$STATE" = "SUCCEEDED" ] && aws athena get-query-results --query-execution-id "$QID" --output text | head -40
