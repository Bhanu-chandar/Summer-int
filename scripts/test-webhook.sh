#!/usr/bin/env bash
#
# Task 6 - verify the GitHub -> Jenkins webhook without pushing code.
#
# 1. Checks the Jenkins webhook endpoint is reachable from the outside.
# 2. Optionally POSTs a minimal GitHub `push` payload to it, exactly as
#    GitHub would, so you can watch the job start.
#
set -euo pipefail

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-https://github.com/<your-github-user>/summerint}"
SIMULATE=0

usage() {
  cat <<'USAGE'
Usage: scripts/test-webhook.sh [options]

  -u, --url URL        Jenkins base URL     (default: http://localhost:8080)
  -r, --repo URL       GitHub repo URL used in the fake payload
  -b, --branch NAME    Branch in the fake payload            (default: main)
      --simulate       Actually POST a fake push event
      --help

Without --simulate this only probes reachability (safe, read-only).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--url)    JENKINS_URL="${2%/}"; shift 2 ;;
    -r|--repo)   REPO_URL="$2"; shift 2 ;;
    -b|--branch) BRANCH="$2"; shift 2 ;;
    --simulate)  SIMULATE=1; shift ;;
    --help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

HOOK="${JENKINS_URL%/}/github-webhook/"

echo "==> Jenkins base : ${JENKINS_URL}"
echo "==> Webhook path : ${HOOK}"
echo

echo "--- 1. is Jenkins up? ---"
if curl -fsS -o /dev/null -w '    HTTP %{http_code} in %{time_total}s\n' "${JENKINS_URL%/}/login"; then
  echo "    Jenkins is reachable."
else
  echo "    Could not reach ${JENKINS_URL}/login" >&2
  echo "    Check the container is running and port 8080 is open in the security group." >&2
  exit 1
fi
echo

echo "--- 2. does the webhook endpoint exist? ---"
# GitHub plugin answers GET with 405/200 depending on version; 404 means the
# GitHub plugin is not installed.
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$HOOK" || true)
echo "    GET ${HOOK} -> HTTP ${CODE}"
case "$CODE" in
  404) echo "    404: the GitHub plugin is not installed. Install 'github' in Jenkins." >&2; exit 1 ;;
  000) echo "    No response - blocked by firewall/security group." >&2; exit 1 ;;
  *)   echo "    Endpoint present (any non-404 is fine here)." ;;
esac
echo

if [[ "$SIMULATE" -ne 1 ]]; then
  echo "Reachability looks good. Re-run with --simulate to fire a fake push event."
  exit 0
fi

echo "--- 3. sending a simulated GitHub push event ---"
OWNER_REPO="$(echo "$REPO_URL" | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
OWNER="${OWNER_REPO%%/*}"
NAME="${OWNER_REPO##*/}"

PAYLOAD=$(cat <<JSON
{
  "ref": "refs/heads/${BRANCH}",
  "before": "0000000000000000000000000000000000000000",
  "after": "1111111111111111111111111111111111111111",
  "repository": {
    "name": "${NAME}",
    "full_name": "${OWNER_REPO}",
    "html_url": "${REPO_URL}",
    "clone_url": "${REPO_URL}.git",
    "git_url": "git://github.com/${OWNER_REPO}.git",
    "ssh_url": "git@github.com:${OWNER_REPO}.git",
    "url": "${REPO_URL}",
    "owner": { "name": "${OWNER}", "login": "${OWNER}" }
  },
  "pusher": { "name": "${OWNER}", "email": "${OWNER}@users.noreply.github.com" }
}
JSON
)

echo "$PAYLOAD" | curl -sS -X POST "$HOOK" \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: push' \
  -H 'X-GitHub-Delivery: 00000000-0000-0000-0000-000000000000' \
  --data-binary @- \
  -o /dev/null -w '    POST -> HTTP %{http_code}\n'

echo
echo "Now check:"
echo "  * Jenkins -> your job -> should show a build starting"
echo "  * Jenkins -> Manage Jenkins -> System Log for 'GitHub' entries"
echo "  * If nothing happens, the job's SCM URL probably does not match ${REPO_URL}"
