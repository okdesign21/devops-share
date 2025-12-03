#!/bin/bash
set -euo pipefail

# Create GitLab directories (idempotent - safe on AMI boot)
mkdir -p /srv/gitlab/data
mkdir -p /srv/gitlab/config

# Check if this is a fresh install or booting from AMI snapshot
SECRETS_FILE="/srv/gitlab/config/gitlab-secrets.json"
if [ -f "$SECRETS_FILE" ]; then
  echo "✓ GitLab secrets already exist (booting from AMI snapshot)"
  EXISTING_SECRETS=true
else
  echo "→ Fresh GitLab install - secrets will be generated"
  EXISTING_SECRETS=false
fi

# Always update .env file (in case external_url or other configs changed)
cat > /opt/gitlab/.env << 'EOF'
GITLAB_EXTERNAL_URL=${external_url}
GITLAB_TRUSTED_CIDRS=${trusted_cidrs}
GITLAB_HOST=${gitlab_host}
GITLAB_DNS_REBINDING_PROTECTION=false
GITLAB_WEBHOOK_WHITELIST=${jenkins_hostname},${vpc_cidr}
EOF

chown root:root /opt/gitlab/.env || true
chmod 640 /opt/gitlab/.env || true

DOCKER_BIN="$(command -v docker)"
cd /opt/gitlab

# Start GitLab container
"$DOCKER_BIN" compose up -d

if [ "$EXISTING_SECRETS" = false ]; then
  echo "→ Waiting for GitLab to initialize and generate secrets (first boot)..."
  sleep 30
  
  # Verify secrets were created
  if [ -f "$SECRETS_FILE" ]; then
    echo "✓ GitLab secrets generated successfully"
  else
    echo "⚠ Warning: Secrets file not found at expected location"
  fi
else
  echo "✓ Using existing secrets - webhooks and encrypted data will work"
fi

echo "✓ GitLab configured with webhook whitelist: ${jenkins_hostname}, ${vpc_cidr}"