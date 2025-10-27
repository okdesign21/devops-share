#!/bin/bash
set -euo pipefail

cat > /opt/jenkins-agent/.env <<'EOF'
JENKINS_URL=${jenkins_url}
EOF

chown root:root /opt/jenkins-agent/.env || true
chmod 640 /opt/jenkins-agent/.env || true

DOCKER_BIN="$(command -v docker)"
"$DOCKER_BIN" compose  up -d --build --force-recreate /opt/jenkins-agent/docker-compose.yml