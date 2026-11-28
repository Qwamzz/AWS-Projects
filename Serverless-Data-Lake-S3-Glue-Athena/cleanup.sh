#!/usr/bin/env bash
# Deletes everything created by deploy.sh.
set -uo pipefail
cd "$(dirname "$0")"; source .deploy.env
REGION=${REGION:-us-east-1}; NAME=${NAME:-cb-datalake-demo}
export AWS_DEFAULT_REGION=$REGION

aws athena delete-work-group --work-group "$WORKGROUP" --recursive-delete-option
aws glue delete-crawler --name "$NAME-raw-orders"
aws glue delete-database --name "$DB"          # also deletes its tables
aws iam delete-role-policy --role-name "$NAME-crawler-role" --policy-name read-raw
aws iam detach-role-policy --role-name "$NAME-crawler-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam delete-role --role-name "$NAME-crawler-role"
aws logs delete-log-stream --log-group-name /aws-glue/crawlers --log-stream-name "$NAME-raw-orders" 2>/dev/null
aws s3 rm "s3://$BUCKET" --recursive >/dev/null
aws s3api delete-bucket --bucket "$BUCKET"
rm -f .deploy.env
echo "All resources deleted."
