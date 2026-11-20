# DevOps Challenge: Flask on EC2 behind an ALB (Terraform + GitHub Actions)

```
Internet ──80──▶ ALB (sg-alb) ──5000──▶ EC2 t3.micro (sg-ec2) ── Docker: Flask /info
                                         ▲ SSH 22 only from ssh_allowed_cidr
GitHub Actions ─▶ build ─▶ ECR ─▶ SSM Run Command ─▶ instance pulls image & restarts container
```

## Layout

| Path | Purpose |
|---|---|
| `terraform/` | EC2, ALB, target group, security groups, IAM role/profile, ECR |
| `.github/workflows/deploy.yml` | Build → push to ECR → deploy via SSM → verify through ALB |
| `app/` | Flask app + Dockerfile (see "Changes to the provided app") |
| `scripts/deploy.sh` | Same deploy, runnable from your laptop |
| `scripts/bootstrap-state-bucket.sh` | One-time: creates the S3 bucket for Terraform state and writes `terraform/backend.hcl` |
| `scripts/setup-github-secrets.sh` | Creates the GitHub Actions secrets/variables from your `.env` |
| `.env.example` | Template for every environment variable (copy to `.env`, which is git-ignored) |
| `docker-compose.yml` | Run the app locally |

## Quick start

### Run locally
```bash
cp .env.example .env
docker compose up --build
curl http://localhost:5000/info     # {"environment":"development","instance_id":"not running on an EC2 instance",...}
curl http://localhost:5000/health   # {"status":"ok"}
```
Without Docker: `pip install -r app/requirements.txt && python app/app.py`.

App environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `APP_ENV` | `development` | Returned in `/info` (`production` on EC2) |
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `5000` | Listen port |
| `IMDS_ENDPOINT` | `http://169.254.169.254/latest` | EC2 metadata service URL |

### Create the GitHub secrets and variables
1. In AWS IAM, create a user for CI (e.g. `github-actions-deploy`) with the permissions listed in section 1 below, then create an **access key** for it.
2. Put the key in `.env` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `PROJECT_NAME`).
3. Install the [GitHub CLI](https://cli.github.com), run `gh auth login`, then:
   ```bash
   ./scripts/setup-github-secrets.sh
   ```
   This creates secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (and `AWS_SESSION_TOKEN` if set) and variables `AWS_REGION` / `PROJECT_NAME`. If `AWS_ROLE_ARN` is set in `.env` it stores that variable instead (OIDC, no keys).

   Or by hand: repo **Settings → Secrets and variables → Actions** → add the same names.

### Full deploy order
1. `./scripts/bootstrap-state-bucket.sh` (once per AWS account: creates the S3 state bucket)
2. `cd terraform && cp terraform.tfvars.example terraform.tfvars && terraform init -backend-config=backend.hcl && terraform apply`
3. `./scripts/setup-github-secrets.sh`
4. GitHub → **Actions → Build and Deploy → Run workflow** (or push to `main`)
5. `curl "$(terraform -chdir=terraform output -raw info_url)"`
6. When finished: `terraform -chdir=terraform destroy`

## Prerequisites
Terraform >= 1.5, AWS CLI v2, Docker (only for manual deploys), an AWS account (Free Tier is fine), and a GitHub repo containing this code.

## 1. Supply AWS credentials

**Terraform / local scripts** read the standard AWS credential chain. Nothing is hardcoded:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...        # only if using temporary credentials
export AWS_REGION=us-east-1
# or: export AWS_PROFILE=myprofile   (or -var aws_profile=myprofile)
```

**GitHub Actions** (Settings → Secrets and variables → Actions). Pick one:

* **Option A: access keys (default).** Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`.
* **Option B: OIDC (recommended for real use).** Variable `AWS_ROLE_ARN` = a role trusting `token.actions.githubusercontent.com` for your repo. When set, keys are ignored.

Optional *variables*: `AWS_REGION` (default `us-east-1`) and `PROJECT_NAME` (default `devops-challenge`). They must match what you gave Terraform.

The CI identity needs roughly: `ecr:*` push actions on the repo + `ecr:GetAuthorizationToken`, `ec2:DescribeInstances`, `ssm:SendCommand` / `GetCommandInvocation` / `DescribeInstanceInformation`, and `elasticloadbalancing:DescribeLoadBalancers`. (Admin works for a test account.)

## 2. Deploy the infrastructure

Terraform state is stored remotely in **S3** (`terraform/backend.tf`), not on your machine: encrypted, versioned, private, with S3-native locking (`use_lockfile`) so two people can't apply at once. The bucket name is not hard-coded; it's passed at init time from `terraform/backend.hcl` (git-ignored).

```bash
./scripts/bootstrap-state-bucket.sh            # once per account: creates <project_name>-tfstate-<account-id> + terraform/backend.hcl
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set ssh_allowed_cidr to your IP/32
terraform init -backend-config=backend.hcl
terraform apply
```

To use your own existing bucket instead, copy `backend.hcl.example` to `backend.hcl` and edit it (or set `TF_STATE_BUCKET` before running the bootstrap script).

Outputs include `info_url`. The instance boots, installs Docker and starts a systemd service that keeps trying to pull `:latest` from ECR. Until the first image is pushed the ALB returns 502/503, which is expected.

## 3. Trigger a deployment

* **GitHub Actions:** push to `main` (changes under `app/`), or Actions → *Build and Deploy* → *Run workflow*. Run it once after `terraform apply` to ship the first image.
* **Manually:** `AWS_REGION=us-east-1 ./scripts/deploy.sh`

Then:

```bash
curl "$(terraform -chdir=terraform output -raw info_url)"
# {"availability_zone":"us-east-1b","instance_id":"i-0abc...","timestamp":"2025-..."}
```

The pipeline tags images with the commit SHA and `latest`, tells the instance (via SSM) to pull the SHA tag and restart the container, then polls the ALB until `/info` returns 200. After a reboot the container returns automatically (systemd).

## 4. Clean up

```bash
cd terraform && terraform destroy
```
(ECR has `force_delete = true`, so images are removed too.)

The state bucket is not managed by Terraform, so it survives `destroy`. To remove it as well (only when you no longer need the state):

```bash
BUCKET=$(grep bucket terraform/backend.hcl | cut -d'"' -f2)
aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' --output json)"
aws s3api delete-bucket --bucket "$BUCKET"
```

## Security design
* ALB SG: inbound 80 from the internet; outbound only to the instance SG on 5000.
* Instance SG: 5000 **only from the ALB SG**; 22 only from `ssh_allowed_cidr` (default `1.2.3.4/32`, so change it if you want SSH).
* IAM instance role: `AmazonSSMManagedInstanceCore` + pull-only access to this one ECR repo.
* IMDSv2 enforced; encrypted gp3 root volume; ECR scan-on-push.
* Deployments use SSM, so SSH is not required by CI and no private key is stored in GitHub.

## Changes to the provided app
`app.py` originally used IMDSv1 calls, which are rejected by an instance enforcing IMDSv2. It now requests an IMDSv2 token first (still falls back to "not running on an EC2 instance" locally). The hop limit is 2 so the container can reach the metadata service. Dockerfile/requirements are unchanged (moved into `app/`).

## Assumptions
* Region has a **default VPC** (or pass `vpc_id` with ≥2 public subnets in different AZs). No NAT gateway is used, so the instance sits in a public subnet with a public IP (its SG still blocks everything except ALB/SSH).
* HTTP only on port 80; no domain/TLS.
* Single instance (no auto scaling), so a deploy has a few seconds of downtime while the container restarts.
* Terraform state lives in an S3 bucket you create once with `scripts/bootstrap-state-bucket.sh` (Terraform can't create the bucket that stores its own state). The `Name` tag and ECR repo name both equal `project_name`, which is how the pipeline finds its targets.
* Terraform and the pipeline use the same account and region.

## Production improvements
HTTPS with ACM + 301 redirect; ASG with ≥2 instances across AZs and rolling/instance-refresh deploys; private subnets with VPC endpoints (ECR, SSM, S3) or NAT; OIDC with a scoped CI role; immutable image tags (no `latest`) with Trivy scanning in CI; gunicorn instead of Flask's dev server; WAF; CloudWatch logs/alarms; tests and `terraform fmt/validate/tflint` in CI; Terraform changes via PR plan/apply workflow.
