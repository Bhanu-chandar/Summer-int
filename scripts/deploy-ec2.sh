#!/usr/bin/env bash
#
# Task 4 - Deploy to EC2.
#
# SSHes into the EC2 instance, pulls the image from Docker Hub, and runs the
# container exposed on the host port of your choice (80 by default, 8080 also
# fine - both are open in the Terraform security group... 8080 is not, see the
# note in --help).
#
# The remote half is idempotent: re-running replaces the container in place.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (override via flags or environment)
# ---------------------------------------------------------------------------
IMAGE_NAME="${IMAGE_NAME:-docker.io/instantprachi/summerint-site}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HOST_PORT="${HOST_PORT:-80}"
CONTAINER_NAME="${CONTAINER_NAME:-summerint-web}"
SSH_USER="${SSH_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
HOST="${HOST:-}"
DRY_RUN=0

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform"

usage() {
  cat <<'USAGE'
Usage: scripts/deploy-ec2.sh [options]

Options:
  -h, --host HOST        Target host/IP. Default: `terraform output -raw public_ip`
  -u, --user USER        SSH user                     (default: ec2-user)
  -k, --key PATH         SSH private key              (default: ~/.ssh/id_rsa)
  -i, --image NAME       Image without tag            (default: docker.io/instantprachi/summerint-site)
  -t, --tag TAG          Image tag                    (default: latest)
  -p, --port PORT        Host port to expose          (default: 80)
  -n, --name NAME        Container name               (default: summerint-web)
      --dry-run          Print the remote script instead of running it
      --help             This message

Environment equivalents: HOST, SSH_USER, SSH_KEY, IMAGE_NAME, IMAGE_TAG,
HOST_PORT, CONTAINER_NAME. For a private image, export DOCKERHUB_USER and
DOCKERHUB_TOKEN and the script will log in on the remote host.

NOTE ON PORT 8080: the Terraform security group opens 80 and 22 only. If you
deploy on 8080, either add an ingress rule for it or reach it through an SSH
tunnel:  ssh -i KEY -L 8080:localhost:8080 USER@HOST
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--host)  HOST="$2"; shift 2 ;;
    -u|--user)  SSH_USER="$2"; shift 2 ;;
    -k|--key)   SSH_KEY="$2"; shift 2 ;;
    -i|--image) IMAGE_NAME="$2"; shift 2 ;;
    -t|--tag)   IMAGE_TAG="$2"; shift 2 ;;
    -p|--port)  HOST_PORT="$2"; shift 2 ;;
    -n|--name)  CONTAINER_NAME="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Resolve the target host
# ---------------------------------------------------------------------------
if [[ -z "$HOST" ]]; then
  if command -v terraform >/dev/null 2>&1 && [[ -d "$TF_DIR" ]]; then
    log "No --host given; asking Terraform"
    HOST="$(cd "$TF_DIR" && terraform output -raw public_ip 2>/dev/null || true)"
  fi
fi

# Same for the key: Terraform knows where it is, so plain `deploy-ec2.sh`
# works even when the key is not the ~/.ssh/id_rsa default.
if [[ ! -f "$SSH_KEY" ]] && command -v terraform >/dev/null 2>&1 && [[ -d "$TF_DIR" ]]; then
  TF_KEY="$(cd "$TF_DIR" && terraform output -raw private_key_path 2>/dev/null || true)"
  if [[ -n "$TF_KEY" && -f "$TF_KEY" ]]; then
    log "Using key from Terraform: $TF_KEY"
    SSH_KEY="$TF_KEY"
  fi
fi
[[ -n "$HOST" ]] || die "No target host. Pass --host <ip>, or run 'terraform apply' first."

IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
log "Host      : ${SSH_USER}@${HOST}"
log "Image     : ${IMAGE}"
log "Publishing: ${HOST_PORT} -> 80  (container: ${CONTAINER_NAME})"

# ---------------------------------------------------------------------------
# The script that runs ON the EC2 instance
# ---------------------------------------------------------------------------
remote_script() {
  cat <<REMOTE
set -euo pipefail

echo "--- docker availability ---"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Run 'terraform apply' (user_data) or the Ansible playbook first." >&2
  exit 1
fi
sudo systemctl is-active --quiet docker || sudo systemctl start docker

${DOCKER_LOGIN_CMD:-}

echo "--- pulling ${IMAGE} ---"
sudo docker pull "${IMAGE}"

echo "--- (re)starting ${CONTAINER_NAME} ---"
sudo docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
sudo docker run -d \\
  --name "${CONTAINER_NAME}" \\
  --restart unless-stopped \\
  -p ${HOST_PORT}:80 \\
  --label com.centurylinklabs.watchtower.enable=true \\
  "${IMAGE}"

echo "--- waiting for health ---"
healthy=0
for i in \$(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${HOST_PORT}/healthz" >/dev/null 2>&1; then
    echo "healthy after \${i} attempt(s)"
    healthy=1
    break
  fi
  sleep 3
done
if [ "\$healthy" -ne 1 ]; then
  echo "container did not become healthy after 60s" >&2
  sudo docker logs --tail 50 "${CONTAINER_NAME}" >&2
  exit 1
fi

echo "--- prune dangling images ---"
sudo docker image prune -f >/dev/null

sudo docker ps --filter "name=${CONTAINER_NAME}" --format 'RUNNING: {{.Names}}  {{.Image}}  {{.Status}}  {{.Ports}}'
REMOTE
}

if [[ -n "${DOCKERHUB_USER:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
  DOCKER_LOGIN_CMD="echo '${DOCKERHUB_TOKEN}' | sudo docker login -u '${DOCKERHUB_USER}' --password-stdin"
  log "Docker Hub login: enabled (user ${DOCKERHUB_USER})"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "--dry-run: remote script below, nothing executed"
  remote_script
  exit 0
fi

[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"

# ---------------------------------------------------------------------------
# Execute remotely
# ---------------------------------------------------------------------------
remote_script | ssh \
  -i "$SSH_KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=15 \
  "${SSH_USER}@${HOST}" 'bash -s'

log "Deployed. Verify with: curl -f http://${HOST}:${HOST_PORT}/healthz"
