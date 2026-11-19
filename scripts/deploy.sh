#!/usr/bin/env bash
# Manual deploy from your machine (same steps as the GitHub Action).
# Requires: aws cli, docker, valid AWS credentials in the environment.
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROJECT="${PROJECT_NAME:-devops-challenge}"
TAG="${1:-manual-$(date +%Y%m%d%H%M%S)}"
cd "$(dirname "$0")/.."

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
IMAGE="$REGISTRY/$PROJECT:$TAG"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build -t "$IMAGE" -t "$REGISTRY/$PROJECT:latest" app/
docker push "$IMAGE"
docker push "$REGISTRY/$PROJECT:latest"

ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=$PROJECT" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
echo "Deploying $IMAGE to $ID"

CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"/usr/local/bin/app-deploy.sh $IMAGE\"]" \
  --query 'Command.CommandId' --output text)
aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$ID" || true
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$ID" \
  --query '[Status,StandardOutputContent,StandardErrorContent]' --output text

DNS=$(aws elbv2 describe-load-balancers --region "$REGION" --names "$PROJECT-alb" --query 'LoadBalancers[0].DNSName' --output text)
echo "Try: curl http://$DNS/info"
