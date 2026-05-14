#!/usr/bin/env bash
set -euo pipefail

echo "Checking for obvious secret files..."

FOUND_FILES="$(find . -maxdepth 8 \( \
  -name "*.pem" -o \
  -name "*.key" -o \
  -name "*.secret" -o \
  -name "generated-secrets.txt" -o \
  -name ".env" -o \
  -name ".env.*" -o \
  -name "service-account*.json" -o \
  -name "credentials*.json" \
\) -print)"

if [ -n "$FOUND_FILES" ]; then
  echo "Potential secret files found:" >&2
  echo "$FOUND_FILES" >&2
  exit 1
fi

echo "Checking tracked files..."

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED_SECRETS="$(git ls-files | grep -E '(\.pem|\.key|\.secret|generated-secrets\.txt|(^|/)\.env(\.|$)|service-account.*\.json|credentials.*\.json)' || true)"
  if [ -n "$TRACKED_SECRETS" ]; then
    echo "Tracked secret-like files found:" >&2
    echo "$TRACKED_SECRETS" >&2
    exit 1
  fi
fi

echo "Checking for project-specific example values..."

if grep -RInE 'Takashi-U|Agari|codex-cloud-proxy|codex-github-proxy-[a-z0-9-]+\.run\.app|751023547790' . \
  --exclude-dir=.git \
  --exclude="pre-public-check.sh" >/tmp/codex_proxy_public_check_hits 2>/dev/null; then
  echo "Project-specific values found. Replace them with placeholders before publishing:" >&2
  cat /tmp/codex_proxy_public_check_hits >&2
  rm -f /tmp/codex_proxy_public_check_hits
  exit 1
fi

rm -f /tmp/codex_proxy_public_check_hits

echo "OK: no obvious secret files or project-specific example values found."
