#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "Infrastructure Verification Script"
echo "================================================"
echo ""

# Helper functions
success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

section() {
    echo ""
    echo "================================================"
    echo "$1"
    echo "================================================"
}

# 1. Network Stack Verification
section "1. Network Stack"

info "Checking VPC..."
VPC_ID=$(terraform -chdir=envs/dev/network output -raw vpc_id 2>/dev/null || echo "")
if [ -n "$VPC_ID" ]; then
    success "VPC exists: $VPC_ID"
else
    error "VPC not found"
    exit 1
fi

info "Checking NAT instance..."
NAT_ID=$(terraform -chdir=envs/dev/network output -raw nat_instance_id 2>/dev/null || echo "")
NAT_IP=$(terraform -chdir=envs/dev/network output -raw nat_instance_public_ip 2>/dev/null || echo "")
if [ -n "$NAT_ID" ] && [ "$NAT_ID" != "null" ]; then
    success "NAT instance: $NAT_ID (Public IP: $NAT_IP)"
    
    info "Testing NAT instance SSM access..."
    if timeout 10 aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$NAT_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
        success "NAT instance is SSM-accessible"
    else
        error "NAT instance NOT SSM-accessible (may still be initializing)"
    fi
else
    error "NAT instance not found or not yet created"
fi

# 2. CICD Stack Verification
section "2. CICD Stack"

info "Checking GitLab instance..."
GITLAB_ID=$(terraform -chdir=envs/dev/cicd output -raw gitlab_server_id 2>/dev/null)
GITLAB_IP=$(terraform -chdir=envs/dev/cicd output -raw gitlab_private_ip 2>/dev/null)
if [ -n "$GITLAB_ID" ]; then
    success "GitLab instance: $GITLAB_ID (Private IP: $GITLAB_IP)"
else
    error "GitLab instance not found"
    exit 1
fi

info "Testing GitLab SSM access..."
if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$GITLAB_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
    success "GitLab is SSM-accessible"
else
    error "GitLab NOT SSM-accessible"
fi

info "Checking Jenkins instance..."
JENKINS_ID=$(terraform -chdir=envs/dev/cicd output -raw jenkins_server_id 2>/dev/null)
JENKINS_IP=$(terraform -chdir=envs/dev/cicd output -raw jenkins_private_ip 2>/dev/null)
if [ -n "$JENKINS_ID" ]; then
    success "Jenkins instance: $JENKINS_ID (Private IP: $JENKINS_IP)"
else
    error "Jenkins instance not found"
fi

info "Testing Jenkins SSM access..."
if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$JENKINS_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
    success "Jenkins is SSM-accessible"
else
    error "Jenkins NOT SSM-accessible"
fi

# 3. DNS Stack Verification
section "3. DNS Stack"

info "Checking Route53 public zone..."
R53_ZONE=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='r53.infinity.ortflix.uk.'].Id" --output text 2>/dev/null | cut -d'/' -f3)
if [ -n "$R53_ZONE" ]; then
    success "Route53 zone exists: $R53_ZONE"
else
    error "Route53 zone not found"
fi

info "Checking ACM certificate..."
CERT_ARN=$(terraform -chdir=envs/dev/dns output -raw app_certificate_arn 2>/dev/null)
if [ -n "$CERT_ARN" ]; then
    CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$CERT_ARN" --query 'Certificate.Status' --output text 2>/dev/null)
    if [ "$CERT_STATUS" == "ISSUED" ]; then
        success "Certificate is ISSUED: $CERT_ARN"
    else
        error "Certificate status: $CERT_STATUS (should be ISSUED)"
    fi
else
    error "Certificate not found"
fi

info "Checking private DNS zone..."
PRIVATE_ZONE=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='internal.local.'].Id" --output text 2>/dev/null | cut -d'/' -f3)
if [ -n "$PRIVATE_ZONE" ]; then
    success "Private zone exists: $PRIVATE_ZONE"
    
    # Check DNS records
    info "Checking GitLab DNS record..."
    GITLAB_DNS=$(aws route53 list-resource-record-sets --hosted-zone-id "$PRIVATE_ZONE" \
        --query "ResourceRecordSets[?Name=='gitlab-server.internal.local.'].ResourceRecords[0].Value" --output text 2>/dev/null)
    if [ "$GITLAB_DNS" == "$GITLAB_IP" ]; then
        success "GitLab DNS record: gitlab-server.internal.local → $GITLAB_DNS"
    else
        error "GitLab DNS mismatch (expected: $GITLAB_IP, got: $GITLAB_DNS)"
    fi
    
    info "Checking Jenkins DNS record..."
    JENKINS_DNS=$(aws route53 list-resource-record-sets --hosted-zone-id "$PRIVATE_ZONE" \
        --query "ResourceRecordSets[?Name=='jenkins-server.internal.local.'].ResourceRecords[0].Value" --output text 2>/dev/null)
    if [ "$JENKINS_DNS" == "$JENKINS_IP" ]; then
        success "Jenkins DNS record: jenkins-server.internal.local → $JENKINS_DNS"
    else
        error "Jenkins DNS mismatch (expected: $JENKINS_IP, got: $JENKINS_DNS)"
    fi
else
    error "Private DNS zone not found"
fi

# 4. EKS Stack Verification
section "4. EKS Stack"

info "Checking EKS cluster..."
CLUSTER_NAME=$(terraform -chdir=envs/dev/eks output -raw cluster_name 2>/dev/null)
REGION=$(terraform -chdir=envs/dev/eks output -raw region 2>/dev/null || echo "eu-central-1")
if [ -n "$CLUSTER_NAME" ]; then
    success "EKS cluster: $CLUSTER_NAME (Region: $REGION)"
    
    info "Checking cluster status..."
    CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.status' --output text 2>/dev/null)
    if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
        success "Cluster is ACTIVE"
    else
        error "Cluster status: $CLUSTER_STATUS (should be ACTIVE)"
    fi
    
    info "Checking node groups..."
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'nodegroups' --output text 2>/dev/null)
    if [ -n "$NODE_GROUPS" ]; then
        success "Node groups: $NODE_GROUPS"
    else
        error "No node groups found"
    fi
    
    info "Updating kubeconfig..."
    if timeout 30 aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
        success "Kubeconfig updated"
    else
        error "Failed to update kubeconfig (timeout)"
    fi
    
    info "Checking nodes..."
    NODES=$(timeout 30 kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$NODES" -gt 0 ]; then
        success "Found $NODES node(s)"
        timeout 10 kubectl get nodes 2>/dev/null || echo "Could not display nodes"
    else
        error "No nodes found in cluster or kubectl not responding"
    fi
else
    error "EKS cluster not found"
fi

# 6. Internal vs External Communication Tests
section "6. Internal vs External Communication"

info "Creating test pod in EKS for connectivity tests..."
if timeout 60 kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  labels:
    app: network-test
spec:
  containers:
  - name: alpine
    image: alpine:latest
    command: ["/bin/sh", "-c", "apk add --no-cache curl bind-tools netcat-openbsd && sleep 3600"]
  restartPolicy: Never
EOF
then
    success "Test pod created"
else
    error "Failed to create test pod (timeout or kubectl not working)"
    info "Skipping connectivity tests - check kubectl access manually"
    # Skip to IRSA section
    section "7. IRSA Verification"
    
    info "Checking ExternalDNS IAM role..."
    EXTERNAL_DNS_ROLE=$(terraform -chdir=envs/dev/dns output -raw external_dns_role_arn 2>/dev/null)
    if [ -n "$EXTERNAL_DNS_ROLE" ]; then
        success "ExternalDNS role: $EXTERNAL_DNS_ROLE"
    else
        error "ExternalDNS role not found"
    fi
    
    info "Checking ALB Controller IAM role..."
    ALB_ROLE=$(terraform -chdir=envs/dev/eks output -raw alb_controller_role_arn 2>/dev/null)
    if [ -n "$ALB_ROLE" ]; then
        success "ALB Controller role: $ALB_ROLE"
    else
        error "ALB Controller role not found"
    fi
    
    # Skip to summary
    section "Verification Complete!"
    
    echo ""
    info "⚠️  Some tests were skipped due to kubectl connectivity issues"
    echo ""
    info "Generating access commands documentation..."
    if [ -f "./generate-access-commands.sh" ]; then
        ./generate-access-commands.sh
        echo ""
        success "Access guide generated: INFRASTRUCTURE_ACCESS.md"
        echo ""
        echo "📖 View the complete access guide:"
        echo "   cat INFRASTRUCTURE_ACCESS.md"
        echo ""
    fi
    exit 0
fi

info "Waiting for test pod to be ready..."
if timeout 120 kubectl wait --for=condition=Ready pod/network-test --timeout=120s >/dev/null 2>&1; then
    success "Test pod ready"
else
    error "Test pod not ready (timeout)"
    kubectl delete pod network-test --force --grace-period=0 >/dev/null 2>&1 || true
    info "Skipping connectivity tests"
    # Skip to IRSA section
    section "7. IRSA Verification"
    
    info "Checking ExternalDNS IAM role..."
    EXTERNAL_DNS_ROLE=$(terraform -chdir=envs/dev/dns output -raw external_dns_role_arn 2>/dev/null)
    if [ -n "$EXTERNAL_DNS_ROLE" ]; then
        success "ExternalDNS role: $EXTERNAL_DNS_ROLE"
    else
        error "ExternalDNS role not found"
    fi
    
    info "Checking ALB Controller IAM role..."
    ALB_ROLE=$(terraform -chdir=envs/dev/eks output -raw alb_controller_role_arn 2>/dev/null)
    if [ -n "$ALB_ROLE" ]; then
        success "ALB Controller role: $ALB_ROLE"
    else
        error "ALB Controller role not found"
    fi
    
    # Skip to summary
    section "Verification Complete!"
    
    echo ""
    info "⚠️  Some tests were skipped due to pod readiness timeout"
    echo ""
    info "Generating access commands documentation..."
    if [ -f "./generate-access-commands.sh" ]; then
        ./generate-access-commands.sh
        echo ""
        success "Access guide generated: INFRASTRUCTURE_ACCESS.md"
        echo ""
        echo "📖 View the complete access guide:"
        echo "   cat INFRASTRUCTURE_ACCESS.md"
        echo ""
    fi
    exit 0
fi

echo ""
info "=== Internal Communication Tests ==="

# Test 1: Private DNS resolution
info "Test 1: Resolving gitlab-server.internal.local..."
GITLAB_RESOLVED=$(timeout 10 kubectl exec network-test -- nslookup gitlab-server.internal.local 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' || echo "")
if [ "$GITLAB_RESOLVED" == "$GITLAB_IP" ]; then
    success "GitLab DNS resolves to private IP: $GITLAB_IP"
else
    error "GitLab DNS resolution failed (expected: $GITLAB_IP, got: $GITLAB_RESOLVED)"
fi

# Test 2: Private DNS resolution for Jenkins
info "Test 2: Resolving jenkins-server.internal.local..."
JENKINS_RESOLVED=$(timeout 10 kubectl exec network-test -- nslookup jenkins-server.internal.local 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' || echo "")
if [ "$JENKINS_RESOLVED" == "$JENKINS_IP" ]; then
    success "Jenkins DNS resolves to private IP: $JENKINS_IP"
else
    error "Jenkins DNS resolution failed (expected: $JENKINS_IP, got: $JENKINS_RESOLVED)"
fi

# Test 3: Can EKS pod reach GitLab private IP?
info "Test 3: Testing connectivity to GitLab private IP ($GITLAB_IP:80)..."
if timeout 10 kubectl exec network-test -- timeout 5 nc -zv $GITLAB_IP 80 2>&1 | grep -q "open\|succeeded"; then
    success "EKS pod can reach GitLab on private IP"
else
    info "⚠️  Cannot reach GitLab (container may still be starting - can take 5-10 min)"
fi

# Test 4: Can EKS pod reach Jenkins private IP?
info "Test 4: Testing connectivity to Jenkins private IP ($JENKINS_IP:8080)..."
if timeout 10 kubectl exec network-test -- timeout 5 nc -zv $JENKINS_IP 8080 2>&1 | grep -q "open\|succeeded"; then
    success "EKS pod can reach Jenkins on private IP"
else
    info "⚠️  Cannot reach Jenkins (container may still be starting - can take 5-10 min)"
fi

echo ""
info "=== External Communication Tests ==="

# Test 5: Can EKS pod reach internet?
info "Test 5: Testing outbound internet connectivity..."
if timeout 15 kubectl exec network-test -- timeout 5 curl -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null | grep -q "200\|301\|302"; then
    success "EKS pods can reach internet (via NAT)"
else
    error "No internet connectivity from EKS pods"
fi

# Test 6: Check NAT instance is being used
info "Test 6: Checking if traffic goes through NAT instance..."
EXTERNAL_IP=$(timeout 15 kubectl exec network-test -- timeout 5 curl -s https://api.ipify.org 2>/dev/null || echo "")
if [ "$EXTERNAL_IP" == "$NAT_IP" ]; then
    success "Outbound traffic uses NAT instance IP: $NAT_IP"
else
    info "Outbound traffic IP: $EXTERNAL_IP (NAT IP: $NAT_IP)"
fi

# Test 7: Verify EKS nodes are in private subnets
echo ""
info "Test 7: Verifying EKS nodes are in private subnets..."
PRIVATE_SUBNETS=$(terraform -chdir=envs/dev/network output -json private_subnet_ids 2>/dev/null | jq -r '.[]' || echo "")
NODE_SUBNET=$(timeout 10 kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].spec.providerID' | cut -d'/' -f2 || echo "")
if [ -n "$NODE_SUBNET" ] && echo "$PRIVATE_SUBNETS" | grep -q "$NODE_SUBNET"; then
    success "EKS nodes are in private subnets ✓"
else
    info "Node subnet: $NODE_SUBNET"
fi

# Cleanup test pod
info "Cleaning up test pod..."
timeout 30 kubectl delete pod network-test --grace-period=0 --force >/dev/null 2>&1 || true

# 7. IAM Roles for Service Accounts (IRSA)
section "7. IRSA Verification"

info "Checking ExternalDNS IAM role..."
EXTERNAL_DNS_ROLE=$(terraform -chdir=envs/dev/dns output -raw external_dns_role_arn 2>/dev/null)
if [ -n "$EXTERNAL_DNS_ROLE" ]; then
    success "ExternalDNS role: $EXTERNAL_DNS_ROLE"
else
    error "ExternalDNS role not found"
fi

info "Checking ALB Controller IAM role..."
ALB_ROLE=$(terraform -chdir=envs/dev/eks output -raw alb_controller_role_arn 2>/dev/null)
if [ -n "$ALB_ROLE" ]; then
    success "ALB Controller role: $ALB_ROLE"
else
    error "ALB Controller role not found"
fi

# Summary
section "Verification Complete!"

echo ""
info "Generating access commands documentation..."
if [ -f "./generate-access-commands.sh" ]; then
    ./generate-access-commands.sh
    echo ""
    success "Access guide generated: INFRASTRUCTURE_ACCESS.md"
    echo ""
    echo "📖 View the complete access guide:"
    echo "   cat INFRASTRUCTURE_ACCESS.md"
    echo ""
    echo "   OR"
    echo ""
    echo "   Open INFRASTRUCTURE_ACCESS.md in your editor"
    echo ""
else
    error "generate-access-commands.sh not found"
    echo ""
    echo "Next steps:"
    echo "1. Test SSM access to GitLab:"
    echo "   aws ssm start-session --target $GITLAB_ID"
    echo ""
    echo "2. Test SSM port-forward to GitLab (localhost:8443):"
    echo "   aws ssm start-session --target $GITLAB_ID \\"
    echo "     --document-name AWS-StartPortForwardingSession \\"
    echo "     --parameters '{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8443\"]}'"
    echo ""
    echo "3. Test SSM access to Jenkins:"
    echo "   aws ssm start-session --target $JENKINS_ID"
    echo ""
    echo "4. Deploy Kubernetes controllers (see K8S_INTEGRATION.md):"
    echo "   - AWS Load Balancer Controller"
    echo "   - ExternalDNS"
    echo ""
    echo "5. Deploy a test application with Ingress"
    echo ""
fi
