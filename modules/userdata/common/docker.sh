#!/usr/bin/env bash
# Installs Docker CE + Compose v2 (plugin) from Docker's official repo (Ubuntu 24.04+)
# Idempotent and resilient with retries.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

retry() {
  local n=0 max=${2:-8} delay=${3:-5}
  until bash -lc "$1"; do
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      echo "Command failed after $n attempts: $1" >&2
      exit 1
    fi
    sleep "$delay"
  done
}

# Base deps
retry "apt-get update -y"
retry "apt-get install -y ca-certificates curl gnupg lsb-release"

# Docker APT repo (keyring)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg > /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \${UBUNTU_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

# Install Docker CE stack + Compose v2 plugin
retry "apt-get update -y"
retry "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

# Enable Docker
systemctl enable --now docker || systemctl enable --now docker.service

# Add common users to docker group (if they exist)
for u in ubuntu ssm-user ec2-user; do
  if id "$u" >/dev/null 2>&1; then
    usermod -aG docker "$u" || true
  fi
done

# Quick smoke test
docker --version || true
docker compose version || true
