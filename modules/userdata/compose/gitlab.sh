#!/bin/bash
set -euxo pipefail

mkdir -p /opt/gitlab
cat > /opt/gitlab/docker-compose.yml <<'YML'
version: "3.8"
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: always
    hostname: gitlab.local
    shm_size: "256m"
    ports:
      - "8080:80"
      - "443:443"
      - "2222:22"
    volumes:
      - ./config:/etc/gitlab
      - ./logs:/var/log/gitlab
      - ./data:/var/opt/gitlab
      - ./git_home:/home/git
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://localhost:8080'
        nginx['listen_https'] = false
        nginx['listen_port'] = 80
        nginx['redirect_http_to_https'] = false
        gitlab_rails['gitlab_relative_url_root'] = '/gitlab'

        gitlab_rails['allow_local_requests_from_web_hooks_and_services'] = true
        gitlab_rails['allow_local_requests_from_system_hooks'] = true
        gitlab_rails['outbound_local_requests_whitelist'] = ['${VPC_CIDR}']

        gitlab_rails['gitlab_shell_ssh_port'] = 2222
        gitlab_rails['trusted_proxies'] = ['${VPC_CIDR}']
        gitlab_rails['trusted_ip_whitelist'] = ['${VPC_CIDR}']

    logging:
      driver: "local"
      options:
        max-size: "10m"
        max-file: "3"
volumes:
  config:
  logs:
  data:
  git_home:
YML

cd /opt/gitlab && /usr/local/bin/docker compose up -d

