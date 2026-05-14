import hashlib
import hmac
import json
import logging
import os
import time
import uuid
from datetime import datetime
from typing import Literal

import jwt
import requests
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field


logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("codex-github-proxy")

app = FastAPI(title="Codex GitHub Restricted Proxy")
bearer = HTTPBearer(auto_error=True)

GITHUB_API = "https://api.github.com"
GITHUB_API_VERSION = os.getenv("GITHUB_API_VERSION", "2022-11-28")

GITHUB_APP_ID = os.environ["GITHUB_APP_ID"]
GITHUB_PRIVATE_KEY_PEM = os.environ["GITHUB_PRIVATE_KEY_PEM"].replace("\\n", "\n")

# Single-installation mode.
GITHUB_INSTALLATION_ID = os.environ.get("GITHUB_INSTALLATION_ID", "")

# Optional multi-installation mode.
# Example:
#   {"owner-one":"11111111","some-org":"22222222"}
GITHUB_INSTALLATION_IDS_JSON = os.environ.get("GITHUB_INSTALLATION_IDS_JSON", "")

BOOTSTRAP_TOKEN_SHA256 = os.environ["BOOTSTRAP_TOKEN_SHA256"]
SESSION_SIGNING_KEY = os.environ["SESSION_SIGNING_KEY"]

# Strict repo allowlist. Recommended.
ALLOWED_REPO_KEYS = {
    item.strip().lower()
    for item in os.getenv("ALLOWED_REPOS", "").split(",")
    if item.strip()
}

# Broader owner allowlist. Convenient, but less strict than ALLOWED_REPOS.
ALLOWED_OWNER_KEYS = {
    item.strip().lower()
    for item in os.getenv("ALLOWED_OWNERS", "").split(",")
    if item.strip()
}

if not ALLOWED_REPO_KEYS and not ALLOWED_OWNER_KEYS:
    raise RuntimeError("Set ALLOWED_REPOS and/or ALLOWED_OWNERS")

SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", str(12 * 60 * 60)))

ALLOWED_OPS = {
    "issue:create",
    "issue:update",
    "issue:comment",
    "pr:create",
    "pr:update",
}

_installation_token_cache: dict[str, dict] = {}


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def constant_time_hash_check(value: str, expected_sha256: str) -> bool:
    return hmac.compare_digest(sha256_text(value), expected_sha256)


def owner_key(owner: str) -> str:
    return owner.strip().lower()


def repo_key(repo: str) -> str:
    return repo.strip().lower()


def parse_repo(repo: str) -> tuple[str, str]:
    if "/" not in repo:
        raise HTTPException(status_code=400, detail="repo must be OWNER/REPO")

    owner, name = repo.split("/", 1)

    if not owner or not name:
        raise HTTPException(status_code=400, detail="repo must be OWNER/REPO")

    return owner, name


def is_repo_allowed(repo: str) -> bool:
    owner, _ = parse_repo(repo)

    if repo_key(repo) in ALLOWED_REPO_KEYS:
        return True

    if owner_key(owner) in ALLOWED_OWNER_KEYS:
        return True

    return False


def assert_repo_allowed(repo: str) -> None:
    if not is_repo_allowed(repo):
        raise HTTPException(status_code=403, detail=f"repo not allowed: {repo}")


def installation_id_for_owner(owner: str) -> str:
    if GITHUB_INSTALLATION_IDS_JSON:
        try:
            mapping_raw = json.loads(GITHUB_INSTALLATION_IDS_JSON)
        except json.JSONDecodeError as exc:
            raise HTTPException(
                status_code=500,
                detail=f"invalid GITHUB_INSTALLATION_IDS_JSON: {exc}",
            )

        mapping = {str(k).lower(): str(v) for k, v in mapping_raw.items()}
        installation_id = mapping.get(owner_key(owner), "").strip()

        if not installation_id:
            raise HTTPException(
                status_code=500,
                detail=f"missing installation id for owner: {owner}",
            )

        return installation_id

    if not GITHUB_INSTALLATION_ID:
        raise HTTPException(
            status_code=500,
            detail="GITHUB_INSTALLATION_ID is not set",
        )

    return GITHUB_INSTALLATION_ID


def github_app_jwt() -> str:
    now = int(time.time())
    payload = {
        "iat": now - 60,
        "exp": now + 9 * 60,
        "iss": GITHUB_APP_ID,
    }
    return jwt.encode(payload, GITHUB_PRIVATE_KEY_PEM, algorithm="RS256")


def parse_github_expires_at(value: str) -> int:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return int(dt.timestamp())


def get_installation_token(repo: str) -> str:
    assert_repo_allowed(repo)

    owner, repo_name = parse_repo(repo)
    installation_id = installation_id_for_owner(owner)

    cache_key = f"{installation_id}:{repo_key(repo)}"
    cached = _installation_token_cache.get(cache_key)
    now = int(time.time())

    if cached and cached["expires_at"] - now > 300:
        return cached["token"]

    app_jwt = github_app_jwt()

    response = requests.post(
        f"{GITHUB_API}/app/installations/{installation_id}/access_tokens",
        headers={
            "Authorization": f"Bearer {app_jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": GITHUB_API_VERSION,
        },
        json={
            # The GitHub App may be installed for all repositories, but each
            # installation token is restricted to the requested repository only.
            "repositories": [repo_name],
            "permissions": {
                "issues": "write",
                "pull_requests": "write",
            },
        },
        timeout=15,
    )

    if response.status_code >= 300:
        raise HTTPException(
            status_code=502,
            detail={
                "message": "failed to create GitHub installation token",
                "status": response.status_code,
                "github": response.text[:1000],
            },
        )

    data = response.json()
    token = data["token"]
    expires_at = parse_github_expires_at(data["expires_at"])

    _installation_token_cache[cache_key] = {
        "token": token,
        "expires_at": expires_at,
    }

    return token


def github_request(method: str, repo: str, path: str, payload: dict | None = None) -> dict:
    token = get_installation_token(repo)

    response = requests.request(
        method,
        f"{GITHUB_API}{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": GITHUB_API_VERSION,
        },
        json=payload,
        timeout=20,
    )

    if response.status_code >= 300:
        raise HTTPException(
            status_code=502,
            detail={
                "message": "GitHub API request failed",
                "status": response.status_code,
                "github": response.text[:2000],
            },
        )

    if response.text:
        return response.json()

    return {"ok": True}


def authenticate_bootstrap(credentials: HTTPAuthorizationCredentials) -> None:
    token = credentials.credentials

    if not constant_time_hash_check(token, BOOTSTRAP_TOKEN_SHA256):
        raise HTTPException(status_code=401, detail="invalid bootstrap token")


def create_session_token(allowed_repo_keys: list[str], allowed_owner_keys: list[str], ops: list[str]) -> str:
    now = int(time.time())

    payload = {
        "iss": "codex-github-proxy",
        "aud": "codex-agent",
        "sub": "codex-agent",
        "allowed_repo_keys": allowed_repo_keys,
        "allowed_owner_keys": allowed_owner_keys,
        "ops": ops,
        "iat": now,
        "exp": now + SESSION_TTL_SECONDS,
        "jti": str(uuid.uuid4()),
    }

    return jwt.encode(payload, SESSION_SIGNING_KEY, algorithm="HS256")


def get_session(credentials: HTTPAuthorizationCredentials = Depends(bearer)) -> dict:
    try:
        return jwt.decode(
            credentials.credentials,
            SESSION_SIGNING_KEY,
            algorithms=["HS256"],
            issuer="codex-github-proxy",
            audience="codex-agent",
            options={"require": ["exp", "iat", "sub", "ops"]},
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail=f"invalid session token: {exc}")


def authorize(session: dict, repo: str, op: str) -> None:
    assert_repo_allowed(repo)

    owner, _ = parse_repo(repo)
    session_allowed_repo_keys = set(session.get("allowed_repo_keys", []))
    session_allowed_owner_keys = set(session.get("allowed_owner_keys", []))

    if repo_key(repo) not in session_allowed_repo_keys and owner_key(owner) not in session_allowed_owner_keys:
        raise HTTPException(status_code=403, detail="session is not valid for this repo")

    if op not in session.get("ops", []):
        raise HTTPException(status_code=403, detail=f"operation not allowed: {op}")


class SessionRequest(BaseModel):
    repos: list[str] | None = None
    owners: list[str] | None = None
    ops: list[str] = Field(
        default=[
            "issue:create",
            "issue:update",
            "issue:comment",
            "pr:create",
            "pr:update",
        ],
        max_length=10,
    )


class IssueCreate(BaseModel):
    repo: str
    title: str = Field(..., min_length=1, max_length=256)
    body: str = Field(default="", max_length=60000)
    labels: list[str] = Field(default_factory=list, max_length=20)
    assignees: list[str] = Field(default_factory=list, max_length=20)


class IssueUpdate(BaseModel):
    repo: str
    number: int = Field(..., ge=1)
    title: str | None = Field(default=None, max_length=256)
    body: str | None = Field(default=None, max_length=60000)
    state: Literal["open", "closed"] | None = None


class IssueComment(BaseModel):
    repo: str
    number: int = Field(..., ge=1)
    body: str = Field(..., min_length=1, max_length=60000)


class PullCreate(BaseModel):
    repo: str
    title: str = Field(..., min_length=1, max_length=256)
    body: str = Field(default="", max_length=60000)
    head: str = Field(..., min_length=1, max_length=200)
    base: str = Field(..., min_length=1, max_length=200)
    draft: bool = False


class PullUpdate(BaseModel):
    repo: str
    number: int = Field(..., ge=1)
    title: str | None = Field(default=None, max_length=256)
    body: str | None = Field(default=None, max_length=60000)
    state: Literal["open", "closed"] | None = None
    base: str | None = Field(default=None, max_length=200)


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/v1/capabilities")
def capabilities() -> dict:
    return {
        "allowed_ops": sorted(ALLOWED_OPS),
        "session_ttl_seconds": SESSION_TTL_SECONDS,
        "allowlist_mode": {
            "allowed_repos_count": len(ALLOWED_REPO_KEYS),
            "allowed_owners_count": len(ALLOWED_OWNER_KEYS),
        },
    }


@app.post("/v1/sessions")
def mint_session(
    body: SessionRequest,
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
) -> dict:
    authenticate_bootstrap(credentials)

    requested_repo_keys = [repo_key(repo) for repo in body.repos] if body.repos else sorted(ALLOWED_REPO_KEYS)
    requested_owner_keys = [owner_key(owner) for owner in body.owners] if body.owners else sorted(ALLOWED_OWNER_KEYS)

    for requested_repo_key in requested_repo_keys:
        if requested_repo_key not in ALLOWED_REPO_KEYS:
            raise HTTPException(status_code=403, detail=f"repo not allowed: {requested_repo_key}")

    for requested_owner_key in requested_owner_keys:
        if requested_owner_key not in ALLOWED_OWNER_KEYS:
            raise HTTPException(status_code=403, detail=f"owner not allowed: {requested_owner_key}")

    for op in body.ops:
        if op not in ALLOWED_OPS:
            raise HTTPException(status_code=403, detail=f"operation not allowed: {op}")

    token = create_session_token(requested_repo_keys, requested_owner_keys, body.ops)

    return {
        "token": token,
        "allowed_repo_keys": requested_repo_keys,
        "allowed_owner_keys": requested_owner_keys,
        "ttl_seconds": SESSION_TTL_SECONDS,
        "ops": body.ops,
    }


@app.post("/v1/issues")
def create_issue(body: IssueCreate, session: dict = Depends(get_session)) -> dict:
    authorize(session, body.repo, "issue:create")
    owner, repo = parse_repo(body.repo)
    logger.info("github_op=issue:create repo=%s", repo_key(body.repo))

    payload = {
        "title": body.title,
        "body": body.body,
    }

    if body.labels:
        payload["labels"] = body.labels

    if body.assignees:
        payload["assignees"] = body.assignees

    return github_request(
        "POST",
        body.repo,
        f"/repos/{owner}/{repo}/issues",
        payload,
    )


@app.patch("/v1/issues")
def update_issue(body: IssueUpdate, session: dict = Depends(get_session)) -> dict:
    authorize(session, body.repo, "issue:update")
    owner, repo = parse_repo(body.repo)
    logger.info("github_op=issue:update repo=%s issue=%s", repo_key(body.repo), body.number)

    payload = {
        key: value
        for key, value in {
            "title": body.title,
            "body": body.body,
            "state": body.state,
        }.items()
        if value is not None
    }

    if not payload:
        raise HTTPException(status_code=400, detail="no fields to update")

    return github_request(
        "PATCH",
        body.repo,
        f"/repos/{owner}/{repo}/issues/{body.number}",
        payload,
    )


@app.post("/v1/issues/comments")
def create_issue_comment(body: IssueComment, session: dict = Depends(get_session)) -> dict:
    authorize(session, body.repo, "issue:comment")
    owner, repo = parse_repo(body.repo)
    logger.info("github_op=issue:comment repo=%s issue=%s", repo_key(body.repo), body.number)

    return github_request(
        "POST",
        body.repo,
        f"/repos/{owner}/{repo}/issues/{body.number}/comments",
        {"body": body.body},
    )


@app.post("/v1/pulls")
def create_pull(body: PullCreate, session: dict = Depends(get_session)) -> dict:
    authorize(session, body.repo, "pr:create")
    owner, repo = parse_repo(body.repo)
    logger.info("github_op=pr:create repo=%s head=%s base=%s", repo_key(body.repo), body.head, body.base)

    return github_request(
        "POST",
        body.repo,
        f"/repos/{owner}/{repo}/pulls",
        {
            "title": body.title,
            "body": body.body,
            "head": body.head,
            "base": body.base,
            "draft": body.draft,
        },
    )


@app.patch("/v1/pulls")
def update_pull(body: PullUpdate, session: dict = Depends(get_session)) -> dict:
    authorize(session, body.repo, "pr:update")
    owner, repo = parse_repo(body.repo)
    logger.info("github_op=pr:update repo=%s pr=%s", repo_key(body.repo), body.number)

    payload = {
        key: value
        for key, value in {
            "title": body.title,
            "body": body.body,
            "state": body.state,
            "base": body.base,
        }.items()
        if value is not None
    }

    if not payload:
        raise HTTPException(status_code=400, detail="no fields to update")

    return github_request(
        "PATCH",
        body.repo,
        f"/repos/{owner}/{repo}/pulls/{body.number}",
        payload,
    )
