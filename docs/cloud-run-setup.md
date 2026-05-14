# Cloud Run setup

## Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="asia-northeast1"
export SERVICE_NAME="codex-github-proxy"
export SERVICE_ACCOUNT_NAME="codex-gh-proxy-sa"

export GITHUB_APP_ID="123456"
export GITHUB_INSTALLATION_ID="987654321"

# Recommended:
export ALLOWED_REPOS="OWNER/REPO"

# Or broader:
# export ALLOWED_OWNERS="OWNER"
```

## Enable APIs

```bash
gcloud config set project "$PROJECT_ID"

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com
```

## Create private key secret

Create `gh-app-private-key` in Secret Manager using the Google Cloud Console UI.

Do not upload the PEM to Cloud Shell.

## Create other secrets

```bash
bash scripts/create-nonkey-secrets.sh
```

Copy the printed `BOOTSTRAP_TOKEN` into Codex Secrets as:

```text
CODEX_GITHUB_PROXY_BOOTSTRAP
```

## Deploy

```bash
bash scripts/deploy-cloud-run.sh
```

## Health check

```bash
export SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region "$REGION" \
  --format='value(status.url)')"

curl -fsS "$SERVICE_URL/health"
```

Expected:

```json
{"ok":true}
```

Use `/health`, not `/healthz`.
