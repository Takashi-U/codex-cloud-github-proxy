# Security Policy

## Reporting vulnerabilities

Do not open a public issue for vulnerabilities involving credential exposure.

Report privately through the maintainer's preferred contact method.

## Never commit secrets

Never commit:

```text
*.pem
*.key
*.secret
generated-secrets.txt
.env
.env.*
service-account*.json
credentials*.json
```

## Private key handling rule

The GitHub App private key PEM file must not be uploaded to Cloud Shell.

Put it directly into Secret Manager through the Google Cloud Console UI.

## If a secret is exposed

### GitHub App private key

1. Delete the GitHub App private key in GitHub.
2. Generate a new private key.
3. Update `gh-app-private-key` in Secret Manager.
4. Deploy a new Cloud Run revision.

### Bootstrap token

1. Run:

   ```bash
   bash scripts/rotate-bootstrap-token.sh
   ```

2. Update Codex Secret:

   ```text
   CODEX_GITHUB_PROXY_BOOTSTRAP
   ```

## Public repository safety

Before pushing publicly:

```bash
bash scripts/pre-public-check.sh
```

Also enable GitHub secret scanning and push protection where available.


## Windows pre-publication check

Before publishing from Windows, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\pre-public-check.ps1
```

This checks for obvious local secret files and, when Git is initialized, secret-like tracked files.
