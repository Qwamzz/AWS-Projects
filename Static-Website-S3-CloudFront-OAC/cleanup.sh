#!/usr/bin/env bash
# Deletes everything created by deploy.sh. Disabling a distribution takes a few minutes.
set -euo pipefail
cd "$(dirname "$0")"
source .deploy.env

echo "Disabling distribution $DIST_ID..."
ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query ETag --output text)
aws cloudfront get-distribution-config --id "$DIST_ID" --query DistributionConfig --output json \
  | sed 's/"Enabled": true/"Enabled": false/' > disabled.json
aws cloudfront update-distribution --id "$DIST_ID" --if-match "$ETAG" \
  --distribution-config file://disabled.json >/dev/null
rm -f disabled.json
aws cloudfront wait distribution-deployed --id "$DIST_ID"

echo "Deleting distribution and OAC..."
ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query ETag --output text)
aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"
OAC_ETAG=$(aws cloudfront get-origin-access-control --id "$OAC_ID" --query ETag --output text)
aws cloudfront delete-origin-access-control --id "$OAC_ID" --if-match "$OAC_ETAG"

echo "Emptying and deleting bucket $BUCKET..."
aws s3 rm "s3://$BUCKET" --recursive >/dev/null
aws s3api delete-bucket --bucket "$BUCKET"
rm -f .deploy.env
echo "All resources deleted."
