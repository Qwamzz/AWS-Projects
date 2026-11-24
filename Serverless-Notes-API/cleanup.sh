#!/usr/bin/env bash
# Deletes every resource created by deploy.sh.
set -uo pipefail

REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-notes-demo}
cd "$(dirname "$0")"

API_ID=${API_ID:-$(cat .api-id 2>/dev/null || aws apigatewayv2 get-apis --region "$REGION" \
  --query "Items[?Name=='$NAME-api'].ApiId | [0]" --output text)}

[ -n "$API_ID" ] && [ "$API_ID" != "None" ] && aws apigatewayv2 delete-api --api-id "$API_ID" --region "$REGION"
aws lambda delete-function --function-name "$NAME" --region "$REGION"
aws dynamodb delete-table --table-name "$NAME" --region "$REGION" >/dev/null
aws iam delete-role-policy --role-name "$NAME-role" --policy-name dynamodb-access
aws iam detach-role-policy --role-name "$NAME-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name "$NAME-role"
aws logs delete-log-group --log-group-name "/aws/lambda/$NAME" --region "$REGION" 2>/dev/null
rm -f .api-id
echo "All resources deleted."
