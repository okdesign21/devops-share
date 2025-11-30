#!/bin/bash
set -euo pipefail

# Wait for Jenkins to write the agent secret to the HTTP endpoint
echo "Waiting for Jenkins to publish agent secret..."

# Derive the Jenkins host from the provided jenkins_url so we don't rely on a hardcoded hostname
JENKINS_URL_INPUT="${jenkins_url}"
JENKINS_HOST="$(echo "$JENKINS_URL_INPUT" | sed -E 's#^https?://([^/:]+).*#\1#')"
SECRET_URL="http://$JENKINS_HOST:8081/docker-secret.txt"
MAX_RETRIES=60
RETRY_COUNT=0
AGENT_SECRET=""

while [ -z "$AGENT_SECRET" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Attempting to fetch agent secret from Jenkins... ($RETRY_COUNT/$MAX_RETRIES)"
  
  AGENT_SECRET=$(curl -sf "$SECRET_URL" 2>/dev/null || echo "")
  
  if [ -z "$AGENT_SECRET" ]; then
    echo "Secret not yet available, waiting 10 seconds..."
    sleep 10
  fi
done

if [ -z "$AGENT_SECRET" ]; then
  echo "ERROR: Could not fetch Jenkins agent secret from $SECRET_URL after $MAX_RETRIES attempts"
  echo "The Jenkins server may not have published the secret yet."
  exit 1
fi

echo "Successfully fetched Jenkins agent secret"

cat > /opt/jenkins-agent/.env <<EOF
JENKINS_URL=${jenkins_url}
JENKINS_AGENT_NAME=docker
JENKINS_SECRET=$AGENT_SECRET
EOF

chown root:root /opt/jenkins-agent/.env || true
chmod 640 /opt/jenkins-agent/.env || true

DOCKER_BIN="$(command -v docker)"
cd /opt/jenkins-agent
"$DOCKER_BIN" compose up -d