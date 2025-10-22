#!/bin/bash
set -euo pipefail

cat > /opt/gitlab/.env <<EOF
GITLAB_EXTERNAL_URL="${external_url}"
GITLAB_TRUSTED_CIDRS="${trusted_cidrs}"
GITLAB_TRUSTED_CIDRS_ARRAY=${trusted_array}
EOF

chown root:root /opt/gitlab/.env || true
chmod 640 /opt/gitlab/.env || true

DOCKER_BIN="$(command -v docker)"
"$DOCKER_BIN" compose up -d -f /opt/gitlab/docker-compose.yml