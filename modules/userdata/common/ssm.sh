#!/bin/bash

# Prefer snap on Ubuntu 20.04+; falls back to systemd unit enable
if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  if command -v snap >/dev/null 2>&1; then
    snap install amazon-ssm-agent --classic
  else
    # minimal fallback using apt repo
    apt-get update
    apt-get install -y amazon-ssm-agent
  fi
fi
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent || systemctl enable --now amazon-ssm-agent || true
