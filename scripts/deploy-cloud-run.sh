#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${REGION:?Set REGION}"
: "${SERVICE_NAME:?Set SERVICE_NAME}"
: "${SERVICE_ACCOUNT_NAME:?Set SERVICE_ACCOUNT_NAME}"

if [ -z "${ALLOWED_REPOS:-}" ] && [ -z "${ALLOWED_OWNERS:-}" ]; then
  echo "Set ALLOWED_REPOS and/or ALLOWED_OWNERS." >&2
  exit 1
fi

SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID" >/dev/null

ENV_VARS="SESSION_TTL_SECONDS=${SESSION_TTL_SECONDS:-43200},GITHUB_API_VERSION=${GITHUB_API_VERSION:-2022-11-28}"

if [ -n "${ALLOWED_REPOS:-}" ]; then
  ENV_VARS="${ENV_VARS},ALLOWED_REPOS=${ALLOWED_REPOS}"
fi

if [ -n "${ALLOWED_OWNERS:-}" ]; then
  ENV_VARS="${ENV_VARS},ALLOWED_OWNERS=${ALLOWED_OWNERS}"
fi

gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --region "$REGION" \
  --service-account "$SERVICE_ACCOUNT" \
  --allow-unauthenticated \
  --ingress all \
  --set-env-vars="$ENV_VARS" \
  --set-secrets="GITHUB_PRIVATE_KEY_PEM=gh-app-private-key:latest,GITHUB_APP_ID=gh-app-id:latest,GITHUB_INSTALLATION_ID=gh-installation-id:latest,BOOTSTRAP_TOKEN_SHA256=codex-proxy-bootstrap-sha256:latest,SESSION_SIGNING_KEY=codex-proxy-session-signing-key:latest"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region "$REGION" \
  --format='value(status.url)')"

echo
echo "Service URL:"
echo "$SERVICE_URL"
echo
echo "Health check:"
curl -fsS "$SERVICE_URL/health"
echo
