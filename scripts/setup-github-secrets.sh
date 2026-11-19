#!/usr/bin/env bash
# Creates the GitHub Actions secrets and variables used by .github/workflows/deploy.yml.
# Requires: GitHub CLI (gh) logged in with `gh auth login`.
# Values are read from .env (copy .env.example to .env first) or the current environment.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

command -v gh >/dev/null || { echo "Install the GitHub CLI: https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login" >&2; exit 1; }

REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "Configuring secrets/variables for $REPO"

# Repository variables (non-secret)
gh variable set AWS_REGION   --repo "$REPO" --body "${AWS_REGION:-us-east-1}"
gh variable set PROJECT_NAME --repo "$REPO" --body "${PROJECT_NAME:-devops-challenge}"

if [ -n "${AWS_ROLE_ARN:-}" ]; then
  # Option B: OIDC role -- no long-lived keys stored in GitHub
  gh variable set AWS_ROLE_ARN --repo "$REPO" --body "$AWS_ROLE_ARN"
  echo "Set AWS_ROLE_ARN (OIDC). Access-key secrets are not needed."
else
  # Option A: access keys as encrypted secrets (values piped via stdin, never echoed)
  : "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID in .env}"
  : "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY in .env}"
  printf '%s' "$AWS_ACCESS_KEY_ID"     | gh secret set AWS_ACCESS_KEY_ID     --repo "$REPO"
  printf '%s' "$AWS_SECRET_ACCESS_KEY" | gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO"
  if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
    printf '%s' "$AWS_SESSION_TOKEN" | gh secret set AWS_SESSION_TOKEN --repo "$REPO"
  fi
  gh variable delete AWS_ROLE_ARN --repo "$REPO" >/dev/null 2>&1 || true
fi

echo
gh secret list   --repo "$REPO"
gh variable list --repo "$REPO"
