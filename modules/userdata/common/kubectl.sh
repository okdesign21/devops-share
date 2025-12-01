#!/usr/bin/env bash
# Installs kubectl + k9s from official repos (Ubuntu 24.04+)

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -LO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
tar -xzf k9s_Linux_amd64.tar.gz
chmod +x k9s
sudo mv k9s /usr/local/bin/
rm k9s_Linux_amd64.tar.gz