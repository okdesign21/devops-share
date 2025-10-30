#!/bin/bash
set -euxo pipefail

mkdir -p /opt/jenkins
cat > /opt/jenkins/docker-compose.yml <<'YML'
services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    restart: unless-stopped
    shm_size: "512m"
    user: "1000:1000"
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - /opt/jenkins/data:/var/jenkins_home
      - /opt/jenkins/config/init.groovy.d:/usr/share/jenkins/ref/init.groovy.d:ro
      - /opt/jenkins/config/casc:/var/jenkins_home/casc:ro
      - /opt/jenkins/config/plugins.txt:/usr/share/jenkins/ref/plugins.txt:ro
      - /opt/jenkins/agent-secrets:/var/jenkins_home/agent-secrets
      - /home/ubuntu/.ssh:/var/jenkins_home/.ssh:ro
      - /opt/jenkins/logs:/var/log/jenkins
    env_file:
      - /opt/jenkins/.env
    environment:
      JAVA_OPTS: >
        -Djenkins.model.Jenkins.crumbIssuerProxyCompatibility=true
        -Dsun.net.http.allowRestrictedHeaders=true
        ${AGENT_HOSTNAME_OVERRIDE:+-Dhudson.TcpSlaveAgentListener.hostName=${AGENT_HOSTNAME_OVERRIDE}}
      JENKINS_OPTS: >-
        --httpPort=8080
      CASC_JENKINS_CONFIG: /var/jenkins_home/casc/jenkins.yaml
      JENKINS_UC_DOWNLOAD: https://updates.jenkins.io/download
    healthcheck:
      test: ["CMD", "bash", "-c", "curl -fsS http://localhost:8080/login > /dev/null"]
      interval: 30s
      timeout: 5s
      retries: 10
    logging:
      driver: "local"
      options:
        max-size: "10m"
        max-file: "3"
  
  # Simple HTTP server to serve agent secrets
  secret-server:
    image: nginx:alpine
    container_name: jenkins-secret-server
    restart: unless-stopped
    ports:
      - "8081:80"
    volumes:
      - /opt/jenkins/agent-secrets:/usr/share/nginx/html:ro
    logging:
      driver: local
      options:
        max-size: "5m"
        max-file: "2"
YML

