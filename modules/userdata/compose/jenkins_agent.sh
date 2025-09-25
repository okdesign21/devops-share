#!/bin/bash
set -euxo pipefail

mkdir -p /opt/jenkins-agent
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
    restart: always
    environment:
      - JENKINS_URL=http://${ALB_DNS}/jenkins
      - JENKINS_AGENT_NAME=docker
      - JENKINS_SECRET=__REPLACE_ME__
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

cd /opt/jenkins-agent && /usr/local/bin/docker-compose up -d

