#!/bin/bash
set -euo pipefail

# Derive the Jenkins host from the provided jenkins_url
JENKINS_URL_INPUT="${jenkins_url}"
JENKINS_HOST="$(echo "$JENKINS_URL_INPUT" | sed -E 's#^https?://([^/:]+).*#\1#')"
SECRET_URL="http://$JENKINS_HOST:8081/docker-secret.txt"

# Create a systemd service that will continuously retry fetching the secret and starting the agent
cat > /etc/systemd/system/jenkins-agent.service <<SYSTEMD
[Unit]
Description=Jenkins Agent
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/jenkins-agent/fetch-and-start.sh
StandardOutput=journal
StandardError=journal
# Restart on failure with exponential backoff
Restart=on-failure
RestartSec=30s
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
SYSTEMD

# Create the fetch-and-start script
cat > /opt/jenkins-agent/fetch-and-start.sh <<'FETCHSCRIPT'
#!/bin/bash
set -euo pipefail

JENKINS_URL="${jenkins_url}"
JENKINS_HOST="$(echo "$JENKINS_URL" | sed -E 's#^https?://([^/:]+).*#\1#')"
SECRET_URL="http://$JENKINS_HOST:8081/docker-secret.txt"

echo "Attempting to fetch Jenkins agent secret from $SECRET_URL"
AGENT_SECRET=$(curl -sf "$SECRET_URL" 2>/dev/null || echo "")

if [ -z "$AGENT_SECRET" ]; then
  echo "ERROR: Could not fetch Jenkins agent secret. Will retry..."
  exit 1
fi

echo "Successfully fetched Jenkins agent secret"

# Create .env file
cat > /opt/jenkins-agent/.env <<EOF
JENKINS_URL=$JENKINS_URL
JENKINS_AGENT_NAME=docker
JENKINS_SECRET=$AGENT_SECRET
EOF

chown root:root /opt/jenkins-agent/.env || true
chmod 640 /opt/jenkins-agent/.env || true

# Start the agent
/opt/jenkins-agent/start-agent.sh
FETCHSCRIPT

chmod +x /opt/jenkins-agent/fetch-and-start.sh

# Enable and start the service
systemctl daemon-reload
systemctl enable jenkins-agent.service
systemctl start jenkins-agent.service

echo "Jenkins agent service configured and started"