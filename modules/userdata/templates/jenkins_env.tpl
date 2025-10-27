#!/bin/bash
set -euo pipefail

cat > /opt/jenkins/.env <<'EOF'
JENKINS_PUBLIC_HOSTNAME=${public_hostname}
JENKINS_URL=${jenkins_url}/
GITLAB_URL=${gitlab_url}
AGENT_HOSTNAME_OVERRIDE=${agent_override}
EOF

chown root:root /opt/jenkins/.env || true
chmod 640 /opt/jenkins/.env || true

DOCKER_BIN="$(command -v docker)"
"$DOCKER_BIN" compose up -d --build --force-recreate /opt/jenkins/docker-compose.yml