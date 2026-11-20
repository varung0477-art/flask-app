#!/usr/bin/env bash
# One-time setup: creates a private, versioned, encrypted S3 bucket for Terraform state
# and writes terraform/backend.hcl. Safe to run again (skips steps that are already done).
# Requires: aws cli with valid credentials (same chain as Terraform).
set -euo pipefail
cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROJECT="${PROJECT_NAME:-devops-challenge}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${TF_STATE_BUCKET:-$PROJECT-tfstate-$ACCOUNT}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket $BUCKET already exists"
else
  echo "Creating bucket $BUCKET in $REGION"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

printf 'bucket = "%s"\nregion = "%s"\n' "$BUCKET" "$REGION" > terraform/backend.hcl
echo "Wrote terraform/backend.hcl. Next:"
echo "  cd terraform && terraform init -backend-config=backend.hcl"
