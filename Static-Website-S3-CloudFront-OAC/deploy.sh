#!/usr/bin/env bash
# Deploys a private S3 bucket + CloudFront distribution with Origin Access Control (OAC).
set -euo pipefail

REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-static-site-demo}
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

echo "Uploading site..."
aws s3 sync site/ "s3://$BUCKET/" --delete >/dev/null

echo "Creating Origin Access Control..."
OAC_ID=$(aws cloudfront create-origin-access-control --origin-access-control-config \
  "Name=$NAME-oac,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
  --query OriginAccessControl.Id --output text)

echo "Creating CloudFront distribution..."
cat > dist-config.json <<EOF
{
  "CallerReference": "$NAME-$(date +%s)",
  "Comment": "Static site (S3 + OAC)",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "PriceClass": "PriceClass_100",
  "HttpVersion": "http2and3",
  "Origins": {"Quantity": 1, "Items": [{
    "Id": "s3-origin",
    "DomainName": "$BUCKET.s3.$REGION.amazonaws.com",
    "OriginAccessControlId": "$OAC_ID",
    "S3OriginConfig": {"OriginAccessIdentity": ""}
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true,
    "AllowedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"],
      "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}}
  },
  "CustomErrorResponses": {"Quantity": 2, "Items": [
    {"ErrorCode": 403, "ResponsePagePath": "/404.html", "ResponseCode": "404", "ErrorCachingMinTTL": 10},
    {"ErrorCode": 404, "ResponsePagePath": "/404.html", "ResponseCode": "404", "ErrorCachingMinTTL": 10}
  ]}
}
EOF
read -r DIST_ID DIST_DOMAIN DIST_ARN < <(aws cloudfront create-distribution \
  --distribution-config file://dist-config.json \
  --query "Distribution.[Id,DomainName,ARN]" --output text)
rm -f dist-config.json

echo "Allowing only this distribution to read the bucket..."
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"AllowCloudFrontServicePrincipalReadOnly\",
    \"Effect\": \"Allow\",
    \"Principal\": {\"Service\": \"cloudfront.amazonaws.com\"},
    \"Action\": \"s3:GetObject\",
    \"Resource\": \"arn:aws:s3:::$BUCKET/*\",
    \"Condition\": {\"StringEquals\": {\"AWS:SourceArn\": \"$DIST_ARN\"}}
  }]
}"

printf "BUCKET=%s\nDIST_ID=%s\nOAC_ID=%s\n" "$BUCKET" "$DIST_ID" "$OAC_ID" > .deploy.env
echo "Waiting for the distribution to deploy (a few minutes)..."
aws cloudfront wait distribution-deployed --id "$DIST_ID"
echo "Done. Site: https://$DIST_DOMAIN"
