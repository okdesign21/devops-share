#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

retry() {
  local n=0 max=${2:-8} delay=${3:-5}
  until bash -lc "$1"; do
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      echo "Command failed after $n attempts: $1"
      exit 1
    fi
    sleep "$delay"
  done
}

# Update and install Docker + curl (with retries to survive first-boot races)
retry "apt-get update"
retry "apt-get install -y docker.io curl"

# Start Docker
systemctl enable --now docker || systemctl enable --now docker.service

if ! dpkg -s docker-compose-plugin >/dev/null 2>&1; then
  retry "apt-get install -y docker-compose-plugin"
fi

for u in ubuntu ssm-user ec2-user; do
  if id "$u" >/dev/null 2>&1; then
    usermod -aG docker "$u" || true
  fi
done
systemctl restart docker || true
