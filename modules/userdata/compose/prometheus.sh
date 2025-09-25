#!/bin/bash

mkdir -p /opt/prometheus
cat > /opt/prometheus/docker-compose.yml <<'YML'
version: "3.8"
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    restart: unless-stopped
YML
cat > /opt/prometheus/prometheus.yml <<'CFG'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'self'
    static_configs:
      - targets: ['localhost:9090']
CFG
cd /opt/prometheus && /usr/local/bin/docker-compose up -d
