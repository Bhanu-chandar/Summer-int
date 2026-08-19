#!/bin/bash
# Bootstraps Docker on Amazon Linux 2023 so the instance is ready for Ansible.
set -euxo pipefail

dnf update -y
dnf install -y docker

systemctl enable --now docker

# Let the default login user run docker without sudo (takes effect next login).
usermod -aG docker ${ssh_user}

# Compose v2 as a docker CLI plugin (not packaged in the AL2023 repos).
COMPOSE_VERSION="v2.29.7"
ARCH="$(uname -m)"
install -d /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-$${ARCH}" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Markers humans and Ansible can check to confirm bootstrap finished.
docker --version        > /var/log/bootstrap-docker.log 2>&1
docker compose version >> /var/log/bootstrap-docker.log 2>&1
touch /var/lib/cloud/bootstrap-complete
