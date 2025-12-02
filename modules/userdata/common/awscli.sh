#!/usr/bin/env bash
# Installs AWS CLI v2 from official sources

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Installing AWS CLI v2..."

# Install unzip if not present
if ! command -v unzip &>/dev/null; then
  apt-get update -qq
  apt-get install -y unzip
fi

# Download and install AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
rm -rf /tmp/awscliv2.zip /tmp/aws

# Verify installation
aws --version

echo "AWS CLI v2 installed successfully"
