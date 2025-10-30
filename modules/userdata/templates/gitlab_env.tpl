#!/bin/bash
set -euo pipefail

cat > /opt/gitlab/.env << 'EOF'
GITLAB_EXTERNAL_URL=${external_url}
GITLAB_TRUSTED_CIDRS=${trusted_cidrs}
GITLAB_HOST=${gitlab_host}
EOF

chown root:root /opt/gitlab/.env || true
chmod 640 /opt/gitlab/.env || true

DOCKER_BIN="$(command -v docker)"
cd /opt/gitlab
"$DOCKER_BIN" compose up -d