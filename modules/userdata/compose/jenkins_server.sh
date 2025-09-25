#!/bin/bash
set -euxo pipefail

mkdir -p /opt/jenkins
cat > /opt/jenkins/docker-compose.yml <<'YML'
version: "3.8"
services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    environment:
      - JAVA_OPTS=-Djenkins.model.Jenkins.crumbIssuerProxyCompatibility=true
      - GITLAB_URL=http://${ALB_DNS}/gitlab	
      - JENKINS_OPTS=--prefix=/jenkins
    volumes:
      - jenkins_home:/var/jenkins_home
    restart: always
volumes:
  jenkins_home:
YML
cd /opt/jenkins && /usr/local/bin/docker-compose up -d

