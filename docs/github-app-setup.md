# GitHub App setup

Create a GitHub App with minimal permissions.

## Settings

```text
Webhook:
  Disabled, unless you explicitly need it

Repository permissions:
  Issues: Read and write
  Pull requests: Read and write
  Metadata: Read-only

Organization permissions:
  None

User permissions:
  None
```

## Installation

Install the app on the target account or organization.

For stricter security, install the app only on selected repositories. If you install it on all repositories, use `ALLOWED_REPOS` or `ALLOWED_OWNERS` carefully.

## Required values

Collect:

```text
GITHUB_APP_ID
GITHUB_INSTALLATION_ID
GitHub App private key PEM
```

The private key PEM must go directly into Secret Manager. Do not upload it to Cloud Shell.

See:

```text
docs/secret-manager-safe-setup.md
```
