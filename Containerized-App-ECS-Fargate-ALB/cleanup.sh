#!/usr/bin/env bash
# Deletes everything created by deploy.sh.
set -uo pipefail
cd "$(dirname "$0")"
source .deploy.env
REGION=${REGION:-us-east-1}
NAME=${NAME:-cb-fargate-demo}

echo "Stopping the service..."
aws ecs update-service --cluster "$NAME" --service "$NAME-svc" --desired-count 0 >/dev/null
aws ecs delete-service --cluster "$NAME" --service "$NAME-svc" --force >/dev/null
aws ecs wait services-inactive --cluster "$NAME" --services "$NAME-svc"

for TD in $(aws ecs list-task-definitions --family-prefix "$NAME" --query "taskDefinitionArns[]" --output text); do
  aws ecs deregister-task-definition --task-definition "$TD" >/dev/null
  aws ecs delete-task-definitions --task-definitions "$TD" >/dev/null 2>&1
done
aws ecs delete-cluster --cluster "$NAME" >/dev/null

echo "Deleting load balancer..."
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

echo "Deleting security groups (retrying while ENIs detach)..."
for SG in "$TASK_SG" "$ALB_SG"; do
  for i in $(seq 1 20); do aws ec2 delete-security-group --group-id "$SG" 2>/dev/null && break; sleep 15; done
done

aws ecr delete-repository --repository-name "$NAME" --force >/dev/null
aws logs delete-log-group --log-group-name "/ecs/$NAME"
aws iam detach-role-policy --role-name "$NAME-exec-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam delete-role --role-name "$NAME-exec-role"
rm -f .deploy.env
echo "All resources deleted."
