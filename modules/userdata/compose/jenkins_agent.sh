#!/bin/bash
set -euxo pipefail

mkdir -p /opt/jenkins-agent

# Create startup script that will be called by systemd
cat > /opt/jenkins-agent/start-agent.sh <<'STARTSCRIPT'
#!/bin/bash
set -euo pipefail

# Pre-build Docker image to save time on first run
if ! docker images jenkins-agent-docker_jenkins-agent 2>/dev/null | grep -q jenkins-agent; then
  echo "Building Jenkins agent Docker image..."
  cd /opt/jenkins-agent
  docker compose build
fi

# The .env file will be created by the fetch-and-start script
if [ -f /opt/jenkins-agent/.env ]; then
  echo "Starting Jenkins agent..."
  cd /opt/jenkins-agent
  docker compose up -d
else
  echo "ERROR: .env file not found. Cannot start agent."
  exit 1
fi
STARTSCRIPT

chmod +x /opt/jenkins-agent/start-agent.sh

cat > /opt/jenkins-agent/Dockerfile <<'DOCKER'
FROM jenkins/inbound-agent:latest
USER root
RUN curl -fsSL https://get.docker.com | sh \
    && groupadd -g 988 docker || true \
    && usermod -aG docker jenkins
RUN apt-get update && apt-get install -y git curl && apt-get clean && rm -rf /var/lib/apt/lists/*
USER jenkins
DOCKER

cat > /opt/jenkins-agent/docker-compose.yml <<'YML'
version: "3.8"
services:
  jenkins-agent:
    container_name: jenkins-agent-docker
    build: .
    image: jenkins-agent-docker_jenkins-agent
    restart: always
    env_file:
      - /opt/jenkins-agent/.env
    environment:
      - JENKINS_WEB_SOCKET=true
      - JENKINS_AGENT_WORKDIR=/home/jenkins/agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - agent_data:/home/jenkins/agent
    working_dir: /home/jenkins/agent
    logging:
      driver: local
      options:
        max-size: "10m"
        max-file: "3"
volumes:
  agent_data:
YML