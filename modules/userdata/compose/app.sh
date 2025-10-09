#!/bin/bash
set -euxo pipefail
mkdir -p /opt/app
cat > /opt/app/docker-compose.yml <<'YML'
version: "3.8"
services:
  app:
    image: okdesign21/weather_app:latest
    ports:
      - "8000:8000"
    restart: unless-stopped
YML

if command -v docker-compose >/dev/null 2>&1; then
  docker-compose -f /opt/app/docker-compose.yml up -d
else
  docker compose -f /opt/app/docker-compose.yml up -d
fi
