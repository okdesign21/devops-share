#!/bin/bash
set -euo pipefail

cat > /opt/gitlab/.env <<EOF
GITLAB_EXTERNAL_URL="${external_url}"
GITLAB_TRUSTED_CIDRS="${trusted_cidrs}"
GITLAB_TRUSTED_CIDRS_ARRAY=${trusted_array}
EOF

chown root:root /opt/gitlab/.env || true
chmod 640 /opt/gitlab/.env || true

if command -v docker compose >/dev/null 2>&1 && [ -f /opt/gitlab/docker-compose.yml ]; then
  docker compose -f /opt/gitlab/docker-compose.yml down || true
  docker compose -f /opt/gitlab/docker-compose.yml up -d || true
fi