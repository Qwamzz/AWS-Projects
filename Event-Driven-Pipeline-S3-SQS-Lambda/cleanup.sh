#!/usr/bin/env bash
# Deletes everything created by deploy.sh.
set -uo pipefail
cd "$(dirname "$0")"
source .deploy.env
REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-pipeline-demo}

for UUID in $(aws lambda list-event-source-mappings --function-name "$NAME" \
    --query "EventSourceMappings[].UUID" --output text); do
  aws lambda delete-event-source-mapping --uuid "$UUID" >/dev/null
done
aws lambda delete-function --function-name "$NAME"
aws logs delete-log-group --log-group-name "/aws/lambda/$NAME" 2>/dev/null
aws sqs delete-queue --queue-url "$QUEUE_URL"
aws sqs delete-queue --queue-url "$DLQ_URL"
aws iam delete-role-policy --role-name "$NAME-role" --policy-name pipeline-access
aws iam detach-role-policy --role-name "$NAME-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name "$NAME-role"
aws s3 rm "s3://$BUCKET" --recursive >/dev/null
aws s3api delete-bucket --bucket "$BUCKET"
rm -f .deploy.env
echo "All resources deleted."
