#!/usr/bin/env bash
# Builds the image, pushes it to ECR and runs it on ECS Fargate behind an ALB.
# Requires Docker locally (see BLOG.md for the CodeBuild alternative).
set -euo pipefail

REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-fargate-demo}
VERSION=${VERSION:-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$NAME
cd "$(dirname "$0")"

echo "1/6 ECR repository + image..."
aws ecr create-repository --repository-name "$NAME" \
  --image-scanning-configuration scanOnPush=true >/dev/null 2>&1 || true
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REPO_URI"
docker build --platform linux/arm64 --build-arg APP_VERSION="$VERSION" -t "$REPO_URI:v$VERSION" app/
docker push "$REPO_URI:v$VERSION"

echo "2/6 Networking (default VPC)..."
VPC_ID=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query "Subnets[0:2].SubnetId" --output text | tr '\t' ',')
ALB_SG=$(aws ec2 create-security-group --group-name "$NAME-alb-sg" --description "ALB: HTTP from anywhere" \
  --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
TASK_SG=$(aws ec2 create-security-group --group-name "$NAME-task-sg" --description "Tasks: 8080 from the ALB only" \
  --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$TASK_SG" --protocol tcp --port 8080 --source-group "$ALB_SG" >/dev/null

echo "3/6 Load balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer --name "$NAME-alb" --type application --scheme internet-facing \
  --subnets ${SUBNETS//,/ } --security-groups "$ALB_SG" --query "LoadBalancers[0].LoadBalancerArn" --output text)
TG_ARN=$(aws elbv2 create-target-group --name "$NAME-tg" --protocol HTTP --port 8080 --vpc-id "$VPC_ID" \
  --target-type ip --health-check-path /health --health-check-interval-seconds 10 --healthy-threshold-count 2 \
  --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 modify-target-group-attributes --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=10 >/dev/null
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null

echo "4/6 Cluster, roles, logs..."
aws ecs create-cluster --cluster-name "$NAME" >/dev/null
aws iam create-role --role-name "$NAME-exec-role" --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Principal": {"Service": "ecs-tasks.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' >/dev/null
aws iam attach-role-policy --role-name "$NAME-exec-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws logs create-log-group --log-group-name "/ecs/$NAME"
aws logs put-retention-policy --log-group-name "/ecs/$NAME" --retention-in-days 7
sleep 10

echo "5/6 Task definition..."
cat > taskdef.json <<EOF
{
  "family": "$NAME",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "256",
  "memory": "512",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/$NAME-exec-role",
  "containerDefinitions": [{
    "name": "web",
    "image": "$REPO_URI:v$VERSION",
    "essential": true,
    "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
    "logConfiguration": {"logDriver": "awslogs", "options": {
      "awslogs-group": "/ecs/$NAME", "awslogs-region": "$REGION", "awslogs-stream-prefix": "web"}}
  }]
}
EOF
aws ecs register-task-definition --cli-input-json file://taskdef.json >/dev/null
rm -f taskdef.json

echo "6/6 Service..."
aws ecs create-service --cluster "$NAME" --service-name "$NAME-svc" --task-definition "$NAME" \
  --desired-count 2 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=web,containerPort=8080" \
  --health-check-grace-period-seconds 30 \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100,deploymentCircuitBreaker={enable=true,rollback=true}" >/dev/null

printf "ALB_ARN=%s\nTG_ARN=%s\nALB_SG=%s\nTASK_SG=%s\n" "$ALB_ARN" "$TG_ARN" "$ALB_SG" "$TASK_SG" > .deploy.env
aws ecs wait services-stable --cluster "$NAME" --services "$NAME-svc"
DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query "LoadBalancers[0].DNSName" --output text)
echo "Done. App: http://$DNS"
