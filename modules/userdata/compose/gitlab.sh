#!/bin/bash
set -euxo pipefail

mkdir -p /opt/gitlab
cat > /opt/gitlab/docker-compose.yml <<'YML'
services:
  gitlab:
    image: gitlab/gitlab-ce:18.2.2-ce.0
    container_name: gitlab
    restart: unless-stopped
    shm_size: "256m"
    ports:
      - "8080:80"
      - "2222:22"
    volumes:
      - /srv/gitlab/data:/var/opt/gitlab
    env_file:
      - /opt/gitlab/.env
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url = '${GITLAB_EXTERNAL_URL}'
        gitlab_rails['gitlab_https'] = false
        nginx['listen_https'] = false
        nginx['listen_port']  = 80
        nginx['redirect_http_to_https'] = false

        nginx['real_ip_header'] = 'X-Forwarded-For'
        nginx['real_ip_recursive'] = 'on'

        nginx['real_ip_trusted_addresses'] = ${GITLAB_TRUSTED_CIDRS_ARRAY}
        gitlab_rails['trusted_proxies']    = ${GITLAB_TRUSTED_CIDRS_ARRAY}

        gitlab_rails['gitlab_shell_ssh_port'] = 2222
        gitlab_rails['allow_local_requests_from_web_hooks_and_services'] = true
        gitlab_rails['allow_local_requests_from_system_hooks'] = true

    logging:
      driver: "local"
      options: { max-size: "10m", max-file: "3" }
YML

