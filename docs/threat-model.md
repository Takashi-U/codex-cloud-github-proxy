# Threat model

## Goals

This project reduces exposure of GitHub credentials inside AI coding agent environments.

It is designed so that:

- Codex does not receive a GitHub PAT.
- Codex does not receive a GitHub App private key.
- Codex does not receive a GitHub installation access token.
- Codex can only call a small set of Issue/PR operations.
- The proxy creates GitHub installation tokens internally and never returns them to Codex.

## Non-goals

This project does not guarantee that the AI agent will never make a bad allowed operation.

If `issue:create` is allowed, the agent can still create a bad issue. If `pr:update` is allowed, the agent can still update a PR incorrectly.

Use an approval layer for higher-risk workflows.

## Credential boundaries

```text
Codex:
  Proxy session token only

Cloud Run:
  GitHub App private key
  Bootstrap token hash
  Session signing key

GitHub:
  Installation access tokens
```

## If the Codex-side proxy session token leaks

The attacker can only call the proxy while the session token is valid, and only for the allowed repositories/owners and operations encoded in that token.

The attacker cannot directly call GitHub with that token.

## If the GitHub App private key leaks

Treat this as serious.

1. Delete the GitHub App private key in GitHub.
2. Generate a new private key.
3. Replace the `gh-app-private-key` Secret Manager value.
4. Deploy a new Cloud Run revision.
5. Check Cloud Run logs.
6. Consider rotating the bootstrap token.

## Recommended hardening

- Prefer `ALLOWED_REPOS` over `ALLOWED_OWNERS`.
- Keep session TTL moderate, for example 4 to 12 hours.
- Do not add arbitrary GitHub API proxying.
- Do not add merge support unless you also add approval.
- Add rate limiting if you expose this beyond personal use.
- Add label and assignee allowlists if needed.
- Review Cloud Run logs regularly.
