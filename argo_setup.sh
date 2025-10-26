#!/usr/bin/env bash
set -euo pipefail

echo "=== ArgoCD Setup Script ==="
echo

# 1. Get the LB hostname for the ArgoCD server
echo "→ Getting ArgoCD server LoadBalancer hostname..."
LB_HOSTNAME=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [[ -z "$LB_HOSTNAME" ]]; then
  echo "Error: LoadBalancer hostname not found. Is ArgoCD deployed?"
  exit 1
fi
echo "LoadBalancer: $LB_HOSTNAME"
echo

# 2. Get initial admin password
echo "→ Retrieving initial admin password..."
INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
if [[ -z "$INITIAL_PASSWORD" ]]; then
  echo "Error: Could not retrieve initial password"
  exit 1
fi
echo "Initial password retrieved"
echo

# 3. Login to ArgoCD
echo "→ Logging in to ArgoCD..."
argocd login "$LB_HOSTNAME" --username admin --password "$INITIAL_PASSWORD" --insecure
echo "Logged in successfully"
echo

# # 4. Update password
# echo "→ Updating admin password..."
# echo "Please enter new admin password:"
# argocd account update-password
# echo "✓ Password updated"
# echo

# # 5. Delete bootstrap secret
# echo "→ Deleting initial admin secret..."
# kubectl -n argocd delete secret argocd-initial-admin-secret
# echo "✓ Bootstrap secret removed"
# echo

# 6. Check cluster-admin permissions
echo "→ Checking cluster-admin permissions..."
CAN_I=$(kubectl auth can-i '*' '*' --all-namespaces)
if [[ "$CAN_I" != "yes" ]]; then
  echo "Warning: You may not have cluster-admin permissions (got: $CAN_I)"
else
  echo "Cluster-admin permissions confirmed"
fi
echo

# 7. Pull IRSA ARNs from Terraform outputs
echo "→ Retrieving IRSA ARNs from Terraform..."
DEV_ALB=$(terraform -chdir=envs/dev/eks output -raw alb_controller_role_arn)
DEV_DNS=$(terraform -chdir=envs/dev/dns output -raw external_dns_role_arn)

if [[ -z "$DEV_ALB" ]] || [[ -z "$DEV_DNS" ]]; then
  echo "Error: Could not retrieve IRSA ARNs"
  echo "   DEV_ALB: $DEV_ALB"
  echo "   DEV_DNS: $DEV_DNS"
  exit 1
fi

echo "ALB Controller ARN: $DEV_ALB"
echo "ExternalDNS ARN: $DEV_DNS"
echo

# 8. Set cluster labels and annotations
echo "→ Configuring in-cluster with labels and IRSA annotations..."
argocd cluster set in-cluster \
  --label env=dev \
  --label clusterName=dev-cluster \
  --label controller.alb=true \
  --label controller.externaldns=true \
  --label controllerNamespace.alb=kube-system \
  --label controllerNamespace.externaldns=external-dns \
  --annotation irsa.alb.arn="${DEV_ALB}" \
  --annotation irsa.externaldns.arn="${DEV_DNS}"

echo "Cluster configured"
echo

# 9. Display cluster configuration
echo "Current cluster configuration:"
argocd cluster list -o wide

echo
echo "=== Setup Complete! ==="
echo "ArgoCD UI: https://$LB_HOSTNAME"
echo "Username: admin"
echo "Password: ${INITIAL_PASSWORD}"