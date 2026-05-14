# codex-github-proxy

A restricted GitHub proxy for Codex Web.

This project lets Codex Web operate on GitHub Issues and Pull Requests without placing a GitHub PAT, GitHub App private key, or GitHub installation access token inside the Codex agent environment.

The recommended deployment target is:

```text
Google Cloud Run + Secret Manager + GitHub App
```

## Important security principle

Do **not** upload the GitHub App private key PEM file to Cloud Shell.

The GitHub App private key must be placed directly into Google Secret Manager, preferably through the Google Cloud Console Secret Manager UI. The file should not be copied into this repository, the Cloud Shell workspace, or any Codex environment.

See:

```text
docs/secret-manager-safe-setup.md
```

## What this project does

- Runs a small FastAPI proxy on Cloud Run.
- Stores GitHub App credentials in Secret Manager.
- Lets Codex obtain a short-lived proxy session token during the setup phase.
- Gives Codex a restricted `gh` shim.
- Allows only:
  - `gh auth token` (repo-scoped, short-lived, fetch use)
  - `gh issue create`
  - `gh issue edit`
  - `gh issue comment`
  - `gh pr create`
  - `gh pr edit`
- Blocks:
  - `gh auth login`
  - `gh auth status`
  - `gh api`
  - arbitrary GitHub REST/GraphQL operations
  - PR merge
  - repository administration

## What this project does not do

- It is not a full GitHub CLI replacement.
- It does not perform `git push`.
- It does not merge PRs.
- It does not expose GitHub credentials to Codex.
- It does not prevent the AI from making mistakes within the operations you explicitly allow.

For stricter workflows, add an approval layer before mutating GitHub.

## Architecture

```text
Codex setup script
  |
  | CODEX_GITHUB_PROXY_BOOTSTRAP
  v
Cloud Run proxy
  |
  | returns short-lived proxy session token
  v
Codex agent phase
  |
  | restricted gh shim
  | Authorization: Bearer <proxy-session-token>
  v
Cloud Run proxy
  |
  | GitHub App JWT
  | GitHub installation access token
  v
GitHub REST API
```

## Repository allowlist modes

This project supports two allowlist modes.

### Recommended: repository allowlist

```bash
export ALLOWED_REPOS="OWNER/repo1,OWNER/repo2"
```

This is stricter and is recommended for public examples and production use.

### Broader: owner allowlist

```bash
export ALLOWED_OWNERS="OWNER"
```

This is convenient, but broader. The proxy still restricts each GitHub installation access token to the specific repository requested in each operation.

You may set both. A repository is allowed if it matches `ALLOWED_REPOS`, or its owner matches `ALLOWED_OWNERS`.

## Quick start

### 1. Create and install a GitHub App

Minimum repository permissions:

```text
Contents: Read-only
Issues: Read and write
Pull requests: Read and write
Metadata: Read-only
```

Disable webhooks unless you need them.

Download the private key from GitHub, then put it directly into Secret Manager. Do **not** upload it to Cloud Shell.

See:

```text
docs/github-app-setup.md
docs/secret-manager-safe-setup.md
```

### 2. Configure Google Cloud

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="asia-northeast1"
export SERVICE_NAME="codex-github-proxy"
export SERVICE_ACCOUNT_NAME="codex-gh-proxy-sa"

export GITHUB_APP_ID="123456"
export GITHUB_INSTALLATION_ID="987654321"

# Prefer repo allowlist:
export ALLOWED_REPOS="OWNER/REPO"

# Or use owner allowlist:
# export ALLOWED_OWNERS="OWNER"
```

Enable APIs:

```bash
gcloud config set project "$PROJECT_ID"

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com
```

### 3. Put the private key into Secret Manager

Use the Cloud Console UI.

Secret name:

```text
gh-app-private-key
```

Do not create `github-app-private-key.pem` in Cloud Shell.

### 4. Create non-key secrets

```bash
bash scripts/create-nonkey-secrets.sh
```

This script does not create any PEM file. It prints `BOOTSTRAP_TOKEN` once. Put that value in Codex Secrets as:

```text
CODEX_GITHUB_PROXY_BOOTSTRAP
```

If you lose the bootstrap token before registering it in Codex, rotate it with:

```bash
bash scripts/rotate-bootstrap-token.sh
```

### 5. Deploy

```bash
bash scripts/deploy-cloud-run.sh
```

### 6. Health check

Use `/health`, not `/healthz`.

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

### 7. Configure Codex Web

Environment variables:

```text
CODEX_GITHUB_PROXY_URL=https://your-cloud-run-service-url
CODEX_GITHUB_ALLOWED_OWNER=OWNER
```

Optional:

```text
GH_REPO=OWNER/REPO
```

Secret:

```text
CODEX_GITHUB_PROXY_BOOTSTRAP=<BOOTSTRAP_TOKEN>
```

Agent internet access:

```text
Allow domain:
  your-cloud-run-service-domain

Allow methods:
  GET
  POST
  PATCH
```

Do not allow `api.github.com` for this workflow.

Paste one of these into your Codex setup script:

```text
examples/codex-setup-script.sh
examples/codex-setup-with-dotnet.sh
```

## Public release checklist

Before pushing this repository to GitHub:

```bash
pwsh -ExecutionPolicy Bypass -File .\scripts\pre-public-check.ps1

# Or, if you are using Bash:
bash scripts/pre-public-check.sh
```

Also verify manually:

```bash
find . -maxdepth 5 \( \
  -name "*.pem" -o \
  -name "*.key" -o \
  -name "*.secret" -o \
  -name "generated-secrets.txt" -o \
  -name ".env" -o \
  -name ".env.*" \
\) -print
```

This should print nothing.

## License

MIT.

### Windows note

`pre-public-check.ps1` is written to work under `Set-StrictMode` in both Windows PowerShell and PowerShell 7.
