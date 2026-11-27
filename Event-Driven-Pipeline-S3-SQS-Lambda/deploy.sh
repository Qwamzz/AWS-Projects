#!/usr/bin/env bash
# Deploys an event-driven pipeline: S3 -> SQS (+ DLQ) -> Lambda -> S3.
set -euo pipefail

REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-pipeline-demo}
BUCKET=${BUCKET:-$NAME-$(date +%s | tail -c 7)}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cd "$(dirname "$0")"

echo "Creating private bucket $BUCKET..."
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Creating queues..."
DLQ_URL=$(aws sqs create-queue --queue-name "$NAME-dlq" \
  --attributes MessageRetentionPeriod=1209600 --query QueueUrl --output text)
DLQ_ARN="arn:aws:sqs:$REGION:$ACCOUNT_ID:$NAME-dlq"
QUEUE_ARN="arn:aws:sqs:$REGION:$ACCOUNT_ID:$NAME-queue"
cat > queue-attrs.json <<EOF
{
  "VisibilityTimeout": "60",
  "RedrivePolicy": "{\"deadLetterTargetArn\":\"$DLQ_ARN\",\"maxReceiveCount\":\"3\"}",
  "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"s3.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"$QUEUE_ARN\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"arn:aws:s3:::$BUCKET\"},\"StringEquals\":{\"aws:SourceAccount\":\"$ACCOUNT_ID\"}}}]}"
}
EOF
QUEUE_URL=$(aws sqs create-queue --queue-name "$NAME-queue" \
  --attributes file://queue-attrs.json --query QueueUrl --output text)
rm -f queue-attrs.json

echo "Creating IAM role..."
aws iam create-role --role-name "$NAME-role" --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' >/dev/null
aws iam attach-role-policy --role-name "$NAME-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name "$NAME-role" --policy-name pipeline-access --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {\"Effect\": \"Allow\", \"Action\": [\"sqs:ReceiveMessage\",\"sqs:DeleteMessage\",\"sqs:GetQueueAttributes\"], \"Resource\": \"$QUEUE_ARN\"},
    {\"Effect\": \"Allow\", \"Action\": \"s3:GetObject\", \"Resource\": \"arn:aws:s3:::$BUCKET/incoming/*\"},
    {\"Effect\": \"Allow\", \"Action\": \"s3:PutObject\", \"Resource\": \"arn:aws:s3:::$BUCKET/processed/*\"}
  ]}"
sleep 12

echo "Creating Lambda function..."
zip -q function.zip app.py
aws lambda create-function --function-name "$NAME" \
  --runtime python3.12 --architectures arm64 --handler app.handler \
  --zip-file fileb://function.zip --role "arn:aws:iam::$ACCOUNT_ID:role/$NAME-role" \
  --timeout 10 --memory-size 128 --environment "Variables={OUTPUT_PREFIX=processed/}" >/dev/null
rm -f function.zip
aws lambda wait function-active-v2 --function-name "$NAME"

echo "Connecting the queue to Lambda..."
aws lambda create-event-source-mapping --function-name "$NAME" \
  --event-source-arn "$QUEUE_ARN" --batch-size 10 --maximum-batching-window-in-seconds 5 \
  --function-response-types ReportBatchItemFailures >/dev/null

echo "Sending S3 upload events to the queue..."
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" --notification-configuration "{
  \"QueueConfigurations\": [{
    \"Id\": \"csv-uploads\",
    \"QueueArn\": \"$QUEUE_ARN\",
    \"Events\": [\"s3:ObjectCreated:*\"],
    \"Filter\": {\"Key\": {\"FilterRules\": [
      {\"Name\": \"prefix\", \"Value\": \"incoming/\"},
      {\"Name\": \"suffix\", \"Value\": \".csv\"}]}}
  }]}"

printf "BUCKET=%s\nQUEUE_URL=%s\nDLQ_URL=%s\n" "$BUCKET" "$QUEUE_URL" "$DLQ_URL" > .deploy.env
echo "Done. Wait a couple of minutes for the notification to take effect, then:"
echo "  aws s3 cp sample-data/sales.csv s3://$BUCKET/incoming/"
