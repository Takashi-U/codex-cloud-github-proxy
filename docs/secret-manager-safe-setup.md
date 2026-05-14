# Safe Secret Manager setup

This document is intentionally strict.

The GitHub App private key PEM file is the most sensitive value in this project. Do not upload it to Cloud Shell. Do not copy it into this repository. Do not create a `github-app-private-key.pem` file in the Cloud Shell workspace.

## Recommended method: Google Cloud Console UI

Use this path for the GitHub App private key.

1. In GitHub, download the GitHub App private key to your local computer.
2. Open Google Cloud Console.
3. Open **Secret Manager**.
4. Click **Create secret**.
5. Name:

   ```text
   gh-app-private-key
   ```

6. In the secret value field, paste the PEM content, or use the console's upload control from your local computer.
7. Use automatic replication unless you have a specific compliance reason to choose user-managed replication.
8. Create the secret.
9. Delete the local PEM file after confirming that the secret exists.

This avoids creating a PEM file in Cloud Shell.

## Do not do this

Do not do this in Cloud Shell:

```bash
gcloud cloudshell scp ...
mv *.pem ./github-app-private-key.pem
cat > github-app-private-key.pem
nano github-app-private-key.pem
```

Do not commit or upload:

```text
*.pem
*.key
*.secret
generated-secrets.txt
.env
service-account*.json
credentials*.json
```

## Non-key secrets

After creating `gh-app-private-key` in Secret Manager, create the other secrets with:

```bash
bash scripts/create-nonkey-secrets.sh
```

This script creates or updates:

```text
gh-app-id
gh-installation-id
codex-proxy-bootstrap-sha256
codex-proxy-session-signing-key
```

It also grants the Cloud Run service account `roles/secretmanager.secretAccessor`.

The script prints the bootstrap token once. Copy it directly into Codex Secrets as:

```text
CODEX_GITHUB_PROXY_BOOTSTRAP
```

The script does not create `generated-secrets.txt`.

## If you previously uploaded the PEM to Cloud Shell

If you previously put the PEM file in Cloud Shell but did not publish it, remove it:

```bash
rm -f github-app-private-key.pem
rm -f generated-secrets.txt
rm -rf __pycache__
```

Then check:

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

If the PEM was committed, pushed, shared, or displayed to others, treat it as leaked:

1. Delete the GitHub App private key in GitHub.
2. Generate a new private key.
3. Replace the `gh-app-private-key` secret value in Secret Manager.
4. Deploy a new Cloud Run revision.
5. Rotate the bootstrap token.


## Windows pre-publication check

On Windows, use the PowerShell check script instead of the Bash script:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\pre-public-check.ps1
```

If PowerShell 7 is not installed:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pre-public-check.ps1
```
