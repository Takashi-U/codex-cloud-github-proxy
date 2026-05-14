#!/usr/bin/env bash
set -euo pipefail

echo "=== Codex restricted GitHub proxy setup started ==="

: "${CODEX_GITHUB_PROXY_URL:?missing CODEX_GITHUB_PROXY_URL}"
: "${CODEX_GITHUB_PROXY_BOOTSTRAP:?missing CODEX_GITHUB_PROXY_BOOTSTRAP secret}"

sudo apt-get update
sudo apt-get install -y curl ca-certificates python3

mkdir -p "$HOME/.codex-gh" "$HOME/.local/bin"
chmod 700 "$HOME/.codex-gh"

SESSION_REQUEST='{}'

if [ -n "${CODEX_GITHUB_ALLOWED_REPO:-}" ]; then
  SESSION_REQUEST="$(python3 - <<'PY'
import json, os
print(json.dumps({"repos": [os.environ["CODEX_GITHUB_ALLOWED_REPO"]]}))
PY
)"
elif [ -n "${CODEX_GITHUB_ALLOWED_OWNER:-}" ]; then
  SESSION_REQUEST="$(python3 - <<'PY'
import json, os
print(json.dumps({"owners": [os.environ["CODEX_GITHUB_ALLOWED_OWNER"]]}))
PY
)"
fi

printf '%s' "$SESSION_REQUEST" \
  | curl -fsS \
      -X POST "$CODEX_GITHUB_PROXY_URL/v1/sessions" \
      -H "Authorization: Bearer $CODEX_GITHUB_PROXY_BOOTSTRAP" \
      -H "Content-Type: application/json" \
      -d @- \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])' \
  > "$HOME/.codex-gh/token"

chmod 600 "$HOME/.codex-gh/token"

cat > "$HOME/.local/bin/codex-gh" <<'PY'
#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

PROXY_URL = os.environ.get("CODEX_GITHUB_PROXY_URL")
TOKEN_PATH = os.path.expanduser("~/.codex-gh/token")


def read_token() -> str:
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        return f.read().strip()


def call(method: str, path: str, payload: dict) -> str:
    if not PROXY_URL:
        raise SystemExit("CODEX_GITHUB_PROXY_URL is not set")

    req = urllib.request.Request(
        PROXY_URL.rstrip("/") + path,
        data=json.dumps(payload).encode("utf-8"),
        method=method,
        headers={
            "Authorization": f"Bearer {read_token()}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return res.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        sys.stderr.write(e.read().decode("utf-8") + "\n")
        raise SystemExit(e.code)


def default_repo() -> str | None:
    return os.environ.get("GH_REPO") or os.environ.get("GITHUB_REPOSITORY") or os.environ.get("CODEX_GITHUB_ALLOWED_REPO")


def add_repo_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("-R", "--repo", default=default_repo(), help="OWNER/REPO")


def require_repo(value: str | None) -> str:
    if not value:
        raise SystemExit("--repo OWNER/REPO is required, or set GH_REPO/GITHUB_REPOSITORY/CODEX_GITHUB_ALLOWED_REPO")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(prog="codex-gh")
    sub = parser.add_subparsers(dest="resource", required=True)

    issue = sub.add_parser("issue")
    issue_sub = issue.add_subparsers(dest="action", required=True)

    issue_create = issue_sub.add_parser("create")
    add_repo_arg(issue_create)
    issue_create.add_argument("--title", required=True)
    issue_create.add_argument("--body", default="")
    issue_create.add_argument("--label", action="append", default=[])
    issue_create.add_argument("--assignee", action="append", default=[])

    issue_edit = issue_sub.add_parser("edit")
    add_repo_arg(issue_edit)
    issue_edit.add_argument("number", type=int)
    issue_edit.add_argument("--title")
    issue_edit.add_argument("--body")
    issue_edit.add_argument("--state", choices=["open", "closed"])

    issue_comment = issue_sub.add_parser("comment")
    add_repo_arg(issue_comment)
    issue_comment.add_argument("number", type=int)
    issue_comment.add_argument("--body", required=True)

    pr = sub.add_parser("pr")
    pr_sub = pr.add_subparsers(dest="action", required=True)

    pr_create = pr_sub.add_parser("create")
    add_repo_arg(pr_create)
    pr_create.add_argument("--title", required=True)
    pr_create.add_argument("--body", default="")
    pr_create.add_argument("--head", required=True)
    pr_create.add_argument("--base", required=True)
    pr_create.add_argument("--draft", action="store_true")

    pr_edit = pr_sub.add_parser("edit")
    add_repo_arg(pr_edit)
    pr_edit.add_argument("number", type=int)
    pr_edit.add_argument("--title")
    pr_edit.add_argument("--body")
    pr_edit.add_argument("--state", choices=["open", "closed"])
    pr_edit.add_argument("--base")

    auth = sub.add_parser("auth")
    auth_sub = auth.add_subparsers(dest="action", required=True)
    auth_token = auth_sub.add_parser("token")
    add_repo_arg(auth_token)

    args = parser.parse_args()

    if args.resource == "issue" and args.action == "create":
        print(call("POST", "/v1/issues", {
            "repo": require_repo(args.repo),
            "title": args.title,
            "body": args.body,
            "labels": args.label,
            "assignees": args.assignee,
        }))
    elif args.resource == "issue" and args.action == "edit":
        print(call("PATCH", "/v1/issues", {
            "repo": require_repo(args.repo),
            "number": args.number,
            "title": args.title,
            "body": args.body,
            "state": args.state,
        }))
    elif args.resource == "issue" and args.action == "comment":
        print(call("POST", "/v1/issues/comments", {
            "repo": require_repo(args.repo),
            "number": args.number,
            "body": args.body,
        }))
    elif args.resource == "pr" and args.action == "create":
        print(call("POST", "/v1/pulls", {
            "repo": require_repo(args.repo),
            "title": args.title,
            "body": args.body,
            "head": args.head,
            "base": args.base,
            "draft": args.draft,
        }))
    elif args.resource == "pr" and args.action == "edit":
        print(call("PATCH", "/v1/pulls", {
            "repo": require_repo(args.repo),
            "number": args.number,
            "title": args.title,
            "body": args.body,
            "state": args.state,
            "base": args.base,
        }))
    elif args.resource == "auth" and args.action == "token":
        data = json.loads(call("POST", "/v1/git/token", {
            "repo": require_repo(args.repo),
        }))
        print(data["token"])
    else:
        raise SystemExit("unsupported command")


if __name__ == "__main__":
    main()
PY

chmod +x "$HOME/.local/bin/codex-gh"

cat > "$HOME/.local/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-} ${2:-}" in
  "issue create")
    exec codex-gh issue create "${@:3}"
    ;;
  "issue edit")
    exec codex-gh issue edit "${@:3}"
    ;;
  "issue comment")
    exec codex-gh issue comment "${@:3}"
    ;;
  "pr create")
    exec codex-gh pr create "${@:3}"
    ;;
  "pr edit")
    exec codex-gh pr edit "${@:3}"
    ;;
  "auth token")
    exec codex-gh auth token "${@:3}"
    ;;
  "auth status"|"auth login")
    echo "Blocked: this environment uses a restricted GitHub proxy and does not expose GitHub tokens." >&2
    exit 2
    ;;
  "api "*)
    echo "Blocked: arbitrary gh api is not allowed in this environment." >&2
    exit 2
    ;;
  *)
    echo "Blocked: restricted gh shim only allows issue/pr create/edit/comment operations." >&2
    exit 2
    ;;
esac
SH

chmod +x "$HOME/.local/bin/gh"

export PATH="$HOME/.local/bin:$PATH"

if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "=== Codex restricted GitHub proxy setup completed ==="
which gh
gh auth token || true
