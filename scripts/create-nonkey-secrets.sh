#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${SERVICE_ACCOUNT_NAME:?Set SERVICE_ACCOUNT_NAME}"
: "${GITHUB_APP_ID:?Set GITHUB_APP_ID}"
: "${GITHUB_INSTALLATION_ID:?Set GITHUB_INSTALLATION_ID}"

SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID" >/dev/null

if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
    --display-name="Codex GitHub Proxy Cloud Run Service Account"
fi

if ! gcloud secrets describe gh-app-private-key >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: Secret Manager secret "gh-app-private-key" does not exist.

Create it first in the Google Cloud Console Secret Manager UI.

Do not upload the GitHub App private key PEM file to Cloud Shell.
See docs/secret-manager-safe-setup.md.
EOF
  exit 1
fi

create_or_add_secret_from_stdin() {
  local name="$1"
  local tmpfile
  tmpfile="$(mktemp)"
  cat > "$tmpfile"

  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    gcloud secrets versions add "$name" --data-file="$tmpfile" >/dev/null
  else
    gcloud secrets create "$name" \
      --replication-policy="automatic" \
      --data-file="$tmpfile" >/dev/null
  fi

  rm -f "$tmpfile"
}

BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN:-$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)}"

BOOTSTRAP_TOKEN_SHA256="$(BOOTSTRAP_TOKEN="$BOOTSTRAP_TOKEN" python3 - <<'PY'
import hashlib
import os
print(hashlib.sha256(os.environ["BOOTSTRAP_TOKEN"].encode()).hexdigest())
PY
)"

SESSION_SIGNING_KEY="${SESSION_SIGNING_KEY:-$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(64))
PY
)}"

printf '%s' "$GITHUB_APP_ID" | create_or_add_secret_from_stdin gh-app-id
printf '%s' "$GITHUB_INSTALLATION_ID" | create_or_add_secret_from_stdin gh-installation-id
printf '%s' "$BOOTSTRAP_TOKEN_SHA256" | create_or_add_secret_from_stdin codex-proxy-bootstrap-sha256
printf '%s' "$SESSION_SIGNING_KEY" | create_or_add_secret_from_stdin codex-proxy-session-signing-key

for SECRET in \
  gh-app-private-key \
  gh-app-id \
  gh-installation-id \
  codex-proxy-bootstrap-sha256 \
  codex-proxy-session-signing-key
do
  gcloud secrets add-iam-policy-binding "$SECRET" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    >/dev/null
done

cat <<EOF

Non-key secrets have been created or updated.

Put this value in Codex Secrets:

CODEX_GITHUB_PROXY_BOOTSTRAP=${BOOTSTRAP_TOKEN}

This script did not write generated-secrets.txt.
Store the bootstrap token in Codex Secrets or a password manager.
EOF
