# Remote state in S3 (nothing is stored on your laptop).
# The bucket and region are supplied at init time so anyone can use their own bucket:
#   ./scripts/bootstrap-state-bucket.sh          # once: creates the bucket + terraform/backend.hcl
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "devops-challenge/terraform.tfstate"
    encrypt      = true # encrypt the state object at rest
    use_lockfile = true # S3-native state locking (Terraform >= 1.10), no DynamoDB table needed
  }
}
