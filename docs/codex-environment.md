# Codex Web environment setup

## Environment variables

Use repo-scoped mode if possible:

```text
CODEX_GITHUB_PROXY_URL=https://your-cloud-run-service-url
CODEX_GITHUB_ALLOWED_REPO=OWNER/REPO
GH_REPO=OWNER/REPO
```

Or owner-scoped mode:

```text
CODEX_GITHUB_PROXY_URL=https://your-cloud-run-service-url
CODEX_GITHUB_ALLOWED_OWNER=OWNER
```

## Secret

```text
CODEX_GITHUB_PROXY_BOOTSTRAP=<BOOTSTRAP_TOKEN>
```

Do not set:

```text
GH_TOKEN
GITHUB_TOKEN
```

## Agent internet access

Allow only the Cloud Run service domain.

Methods:

```text
GET
POST
PATCH
```

Do not allow `api.github.com` for this restricted proxy workflow.

## Setup script

Use one of:

```text
examples/codex-setup-script.sh
examples/codex-setup-with-dotnet.sh
```

## Expected behavior in Codex

```bash
gh auth token
```

Expected result:

```text
Blocked: this environment uses a restricted GitHub proxy and does not expose GitHub tokens.
```

Issue example:

```bash
gh issue create \
  --repo OWNER/REPO \
  --title "Example issue" \
  --body "Created through the restricted proxy."
```

PR example:

```bash
gh pr create \
  --repo OWNER/REPO \
  --title "Example PR" \
  --body "Created through the restricted proxy." \
  --head feature/example \
  --base main
```
