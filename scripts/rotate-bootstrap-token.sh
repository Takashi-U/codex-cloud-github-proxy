#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"

gcloud config set project "$PROJECT_ID" >/dev/null

BOOTSTRAP_TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"

BOOTSTRAP_TOKEN_SHA256="$(BOOTSTRAP_TOKEN="$BOOTSTRAP_TOKEN" python3 - <<'PY'
import hashlib
import os
print(hashlib.sha256(os.environ["BOOTSTRAP_TOKEN"].encode()).hexdigest())
PY
)"

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
printf '%s' "$BOOTSTRAP_TOKEN_SHA256" > "$tmpfile"

if gcloud secrets describe codex-proxy-bootstrap-sha256 >/dev/null 2>&1; then
  gcloud secrets versions add codex-proxy-bootstrap-sha256 --data-file="$tmpfile" >/dev/null
else
  gcloud secrets create codex-proxy-bootstrap-sha256 \
    --replication-policy="automatic" \
    --data-file="$tmpfile" >/dev/null
fi

cat <<EOF

Bootstrap token rotated.

Update Codex Secret:

CODEX_GITHUB_PROXY_BOOTSTRAP=${BOOTSTRAP_TOKEN}

EOF
