#!/usr/bin/env bash
# Deploys the Serverless Notes API: DynamoDB + IAM role + Lambda + HTTP API.
set -euo pipefail

REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-notes-demo}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cd "$(dirname "$0")"

echo "Creating DynamoDB table..."
aws dynamodb create-table --table-name "$NAME" \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region "$REGION" >/dev/null

echo "Creating IAM role..."
aws iam create-role --role-name "$NAME-role" --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' >/dev/null
aws iam attach-role-policy --role-name "$NAME-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name "$NAME-role" --policy-name dynamodb-access --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{\"Effect\": \"Allow\",
    \"Action\": [\"dynamodb:PutItem\",\"dynamodb:GetItem\",\"dynamodb:Scan\",\"dynamodb:DeleteItem\"],
    \"Resource\": \"arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$NAME\"}]}"

echo "Waiting for IAM role to propagate..."
sleep 12

echo "Creating Lambda function..."
zip -q function.zip app.py
aws lambda create-function --function-name "$NAME" \
  --runtime python3.12 --architectures arm64 --handler app.handler \
  --zip-file fileb://function.zip --role "arn:aws:iam::$ACCOUNT_ID:role/$NAME-role" \
  --environment "Variables={TABLE_NAME=$NAME}" --timeout 10 --memory-size 128 \
  --region "$REGION" >/dev/null
rm -f function.zip

echo "Creating HTTP API..."
API_ID=$(aws apigatewayv2 create-api --name "$NAME-api" --protocol-type HTTP \
  --query ApiId --output text --region "$REGION")
INTEGRATION_ID=$(aws apigatewayv2 create-integration --api-id "$API_ID" \
  --integration-type AWS_PROXY --payload-format-version 2.0 \
  --integration-uri "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$NAME" \
  --query IntegrationId --output text --region "$REGION")
for ROUTE in "GET /notes" "POST /notes" "GET /notes/{id}" "DELETE /notes/{id}"; do
  aws apigatewayv2 create-route --api-id "$API_ID" --route-key "$ROUTE" \
    --target "integrations/$INTEGRATION_ID" --region "$REGION" >/dev/null
done
aws apigatewayv2 create-stage --api-id "$API_ID" --stage-name '$default' \
  --auto-deploy --region "$REGION" >/dev/null
aws lambda add-permission --function-name "$NAME" --statement-id apigw-invoke \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*" --region "$REGION" >/dev/null

echo "$API_ID" > .api-id
echo "Done. API endpoint: https://$API_ID.execute-api.$REGION.amazonaws.com"
