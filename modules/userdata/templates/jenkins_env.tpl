#!/bin/bash
set -euo pipefail

cat > /opt/jenkins/.env <<'EOF'
JENKINS_PUBLIC_HOSTNAME=${public_hostname}
JENKINS_URL=${jenkins_url}
GITLAB_URL=${gitlab_url}
AGENT_HOSTNAME_OVERRIDE=${agent_override}
EOF

chown root:root /opt/jenkins/.env || true
chmod 640 /opt/jenkins/.env || true

# If Jenkins is run via docker-compose, restart to pick up the new env
if command -v docker compose >/dev/null 2>&1 && [ -f /opt/jenkins/jenkins/compose.yml ]; then
  docker compose -f /opt/jenkins/jenkins/compose.yml down || true
  docker compose -f /opt/jenkins/jenkins/compose.yml up -d || true
fi