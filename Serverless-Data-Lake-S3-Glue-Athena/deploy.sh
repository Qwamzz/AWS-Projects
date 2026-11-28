#!/usr/bin/env bash
# Builds a small serverless data lake: S3 (raw + curated) -> Glue Crawler/Data Catalog -> Athena.
set -euo pipefail

REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-datalake-demo}
BUCKET=${BUCKET:-$NAME-$(date +%s | tail -c 7)}
DB=${DB:-sales_lake}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION=$REGION
cd "$(dirname "$0")"

[ -d sample-data/orders ] || python3 scripts/generate_orders.py

echo "Creating private bucket $BUCKET..."
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" >/dev/null
else
  aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
# Athena query results are temporary: expire them after 7 days.
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration '{
  "Rules": [{"ID": "expire-athena-results", "Status": "Enabled",
             "Filter": {"Prefix": "athena-results/"}, "Expiration": {"Days": 7}}]}'

echo "Uploading raw CSV data (Hive-style partitions)..."
aws s3 cp sample-data/orders "s3://$BUCKET/raw/orders/" --recursive >/dev/null

echo "Creating Glue database and crawler role..."
aws glue create-database --database-input "{\"Name\": \"$DB\", \"Description\": \"Demo sales data lake\"}"
aws iam create-role --role-name "$NAME-crawler-role" --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Principal": {"Service": "glue.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' >/dev/null
aws iam attach-role-policy --role-name "$NAME-crawler-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam put-role-policy --role-name "$NAME-crawler-role" --policy-name read-raw --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {\"Effect\": \"Allow\", \"Action\": \"s3:GetObject\", \"Resource\": \"arn:aws:s3:::$BUCKET/raw/*\"},
    {\"Effect\": \"Allow\", \"Action\": \"s3:ListBucket\", \"Resource\": \"arn:aws:s3:::$BUCKET\",
     \"Condition\": {\"StringLike\": {\"s3:prefix\": [\"raw/*\"]}}}
  ]}"
sleep 12

echo "Creating and running the crawler..."
aws glue create-crawler --name "$NAME-raw-orders" --database-name "$DB" \
  --role "arn:aws:iam::$ACCOUNT_ID:role/$NAME-crawler-role" \
  --targets "{\"S3Targets\": [{\"Path\": \"s3://$BUCKET/raw/orders/\"}]}" \
  --schema-change-policy UpdateBehavior=UPDATE_IN_DATABASE,DeleteBehavior=LOG \
  --configuration '{"Version":1.0,"Grouping":{"TableGroupingPolicy":"CombineCompatibleSchemas"}}'
aws glue start-crawler --name "$NAME-raw-orders"
until [ "$(aws glue get-crawler --name "$NAME-raw-orders" --query Crawler.State --output text)" = "READY" ]; do
  sleep 15; echo "  crawler running..."
done
aws glue get-crawler-metrics --crawler-name-list "$NAME-raw-orders" \
  --query "CrawlerMetricsList[0].[TablesCreated,TablesUpdated]" --output text

echo "Creating Athena workgroup with a per-query scan limit..."
# Enforcement stays off: an enforced output location blocks CTAS with external_location.
aws athena create-work-group --name "$NAME" --configuration "{
  \"ResultConfiguration\": {\"OutputLocation\": \"s3://$BUCKET/athena-results/\"},
  \"EnforceWorkGroupConfiguration\": false,
  \"PublishCloudWatchMetricsEnabled\": true,
  \"BytesScannedCutoffPerQuery\": 1073741824
}"

printf "BUCKET=%s\nDB=%s\nWORKGROUP=%s\n" "$BUCKET" "$DB" "$NAME" > .deploy.env
echo "Done. Run queries with ./run-query.sh queries/01-revenue-by-category.sql"
