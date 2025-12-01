#!/bin/bash
set -e

# Environment parameter (default to dev)
ENV="${1:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "Infrastructure Verification Script"
echo "Environment: $ENV"
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
VPC_ID=$(terraform -chdir=envs/$ENV/network output -raw vpc_id 2>/dev/null || echo "")
if [ -n "$VPC_ID" ]; then
    success "VPC exists: $VPC_ID"
else
    error "VPC not found"
    exit 1
fi

info "Checking NAT instance..."
NAT_ID=$(terraform -chdir=envs/$ENV/network output -raw nat_instance_id 2>/dev/null || echo "")
NAT_IP=$(terraform -chdir=envs/$ENV/network output -raw nat_instance_public_ip 2>/dev/null || echo "")
if [ -n "$NAT_ID" ] && [ "$NAT_ID" != "null" ]; then
    success "NAT instance: $NAT_ID (Public IP: $NAT_IP)"
    
    info "Testing NAT instance SSM access..."
    if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$NAT_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
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
GITLAB_ID=$(terraform -chdir=envs/$ENV/cicd output -raw gitlab_server_id 2>/dev/null)
GITLAB_IP=$(terraform -chdir=envs/$ENV/cicd output -raw gitlab_private_ip 2>/dev/null)
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
JENKINS_ID=$(terraform -chdir=envs/$ENV/cicd output -raw jenkins_server_id 2>/dev/null)
JENKINS_IP=$(terraform -chdir=envs/$ENV/cicd output -raw jenkins_private_ip 2>/dev/null)
if [ -n "$JENKINS_ID" ]; then
    success "Jenkins instance: $JENKINS_ID (Private IP: $JENKINS_IP)"
else
    error "Jenkins instance not found"
fi

info "Testing Jenkins SSM access..."
if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$JENKINS_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
    success "Jenkins is SSM-accessible"
    
    info "Checking Jenkins containers..."
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$JENKINS_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["docker ps --filter name=jenkins --format \"{{.Names}}: {{.Status}}\""]' \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)
    
    if [ -n "$COMMAND_ID" ]; then
        sleep 2
        DOCKER_STATUS=$(aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$JENKINS_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null)
        
        if echo "$DOCKER_STATUS" | grep -q "jenkins-secret-server.*Up"; then
            success "Jenkins secret server is running (port 8081)"
        else
            info "⚠️  Jenkins containers status: $DOCKER_STATUS"
        fi
    fi

    info "Checking Jenkins agent connectivity (node: docker)..."
    AGENT_CMD_ID=$(aws ssm send-command \
        --instance-ids "$JENKINS_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["if [ -s /opt/jenkins/agent-secrets/docker-ready ]; then echo ONLINE; elif [ -s /opt/jenkins/agent-secrets/docker-timeout ]; then echo TIMEOUT; else echo WAITING; fi"]' \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)

    if [ -n "$AGENT_CMD_ID" ]; then
        sleep 2
        AGENT_STATUS=$(aws ssm get-command-invocation \
            --command-id "$AGENT_CMD_ID" \
            --instance-id "$JENKINS_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null | tr -d '\r')

        case "$AGENT_STATUS" in
            *ONLINE*)
                success "Jenkins agent 'docker' is ONLINE"
                ;;
            *WAITING*)
                info "⚠️  Jenkins agent 'docker' not connected yet (waiting)"
                ;;
            *TIMEOUT*)
                error "Jenkins agent 'docker' did not connect within server boot window"
                ;;
            *)
                info "Agent status unknown (output: $AGENT_STATUS)"
                ;;
        esac
    else
        info "Could not query agent connectivity via SSM"
    fi
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
CERT_ARN=$(terraform -chdir=envs/$ENV/dns output -raw app_certificate_arn 2>/dev/null)
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
PRIVATE_ZONE=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='vpc.internal.'].Id" --output text 2>/dev/null | cut -d'/' -f3)
if [ -n "$PRIVATE_ZONE" ]; then
    success "Private zone exists: $PRIVATE_ZONE"
    
    # Check DNS records
    info "Checking GitLab DNS record..."
    GITLAB_DNS=$(aws route53 list-resource-record-sets --hosted-zone-id "$PRIVATE_ZONE" \
    --query "ResourceRecordSets[?Name=='gitlab-server.vpc.internal.'].ResourceRecords[0].Value" --output text 2>/dev/null)
    if [ "$GITLAB_DNS" == "$GITLAB_IP" ]; then
    success "GitLab DNS record: gitlab-server.vpc.internal → $GITLAB_DNS"
    else
        error "GitLab DNS mismatch (expected: $GITLAB_IP, got: $GITLAB_DNS)"
    fi
    
    info "Checking Jenkins DNS record..."
    JENKINS_DNS=$(aws route53 list-resource-record-sets --hosted-zone-id "$PRIVATE_ZONE" \
    --query "ResourceRecordSets[?Name=='jenkins-server.vpc.internal.'].ResourceRecords[0].Value" --output text 2>/dev/null)
    if [ "$JENKINS_DNS" == "$JENKINS_IP" ]; then
    success "Jenkins DNS record: jenkins-server.vpc.internal → $JENKINS_DNS"
    else
        error "Jenkins DNS mismatch (expected: $JENKINS_IP, got: $JENKINS_DNS)"
    fi
else
    error "Private DNS zone not found"
fi

# 4. EKS Stack Verification
section "4. EKS Stack"

info "Checking EKS cluster..."
CLUSTER_NAME=$(terraform -chdir=envs/$ENV/eks output -raw cluster_name 2>/dev/null)
REGION=$(terraform -chdir=envs/$ENV/eks output -raw region 2>/dev/null || echo "eu-central-1")
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
    if aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
        success "Kubeconfig updated"
    else
        error "Failed to update kubeconfig"
    fi
    
    info "Checking nodes..."
    if NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ') && [ "$NODES" -gt 0 ]; then
        success "Found $NODES node(s)"
        kubectl get nodes 2>/dev/null || echo "Could not display nodes"
    else
        error "No nodes found in cluster or kubectl not responding"
    fi
else
    error "EKS cluster not found"
fi

# 6. Internal vs External Communication Tests
section "6. Internal vs External Communication"

info "Creating test pod in EKS for connectivity tests..."
if kubectl apply -f - >/dev/null 2>&1 <<'EOF'
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
    info "Skipping connectivity tests"
fi

info "Waiting for test pod to be ready..."
if kubectl wait --for=condition=Ready pod/network-test --timeout=180s >/dev/null 2>&1; then
    success "Test pod ready"
    
    echo ""
    info "=== Internal Communication Tests ==="
    
    # Test 1: Private DNS resolution
    info "Test 1: Resolving gitlab-server.vpc.internal..."
    GITLAB_RESOLVED=$(kubectl exec network-test -- nslookup gitlab-server.vpc.internal 2>/dev/null | grep -A1 "Name:.*gitlab-server.vpc.internal" | grep "Address:" | awk '{print $2}' || echo "")
    if [ "$GITLAB_RESOLVED" == "$GITLAB_IP" ]; then
        success "GitLab DNS resolves to private IP: $GITLAB_IP"
    else
        error "GitLab DNS resolution failed (expected: $GITLAB_IP, got: $GITLAB_RESOLVED)"
    fi
    
    # Test 2: Private DNS resolution for Jenkins
    info "Test 2: Resolving jenkins-server.vpc.internal..."
    JENKINS_RESOLVED=$(kubectl exec network-test -- nslookup jenkins-server.vpc.internal 2>/dev/null | grep -A1 "Name:.*jenkins-server.vpc.internal" | grep "Address:" | awk '{print $2}' || echo "")
    if [ "$JENKINS_RESOLVED" == "$JENKINS_IP" ]; then
        success "Jenkins DNS resolves to private IP: $JENKINS_IP"
    else
        error "Jenkins DNS resolution failed (expected: $JENKINS_IP, got: $JENKINS_RESOLVED)"
    fi
    
    # Test 3: Can EKS pod reach GitLab private IP?
    info "Test 3: Testing connectivity to GitLab private IP ($GITLAB_IP:80)..."
    if kubectl exec network-test -- timeout 5 nc -zv $GITLAB_IP 80 2>&1 | grep -q "open\|succeeded"; then
        success "EKS pod can reach GitLab on private IP"
    else
        info "⚠️  Cannot reach GitLab (container may still be starting - can take 5-10 min)"
    fi
    
    # Test 4: Can EKS pod reach Jenkins private IP?
    info "Test 4: Testing connectivity to Jenkins private IP ($JENKINS_IP:8080)..."
    if kubectl exec network-test -- timeout 5 nc -zv $JENKINS_IP 8080 2>&1 | grep -q "open\|succeeded"; then
        success "EKS pod can reach Jenkins on private IP"
    else
        info "⚠️  Cannot reach Jenkins (container may still be starting - can take 5-10 min)"
    fi
    
    echo ""
    info "=== External Communication Tests ==="
    
    # Test 5: Can EKS pod reach internet?
    info "Test 5: Testing outbound internet connectivity..."
    if kubectl exec network-test -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://www.google.com 2>/dev/null | grep -q "200\|301\|302"; then
        success "EKS pods can reach internet (via NAT)"
    else
        error "No internet connectivity from EKS pods"
    fi
    
    # Test 6: Check NAT instance is being used
    info "Test 6: Checking if traffic goes through NAT instance..."
    EXTERNAL_IP=$(kubectl exec network-test -- curl -s --connect-timeout 10 https://api.ipify.org 2>/dev/null || echo "")
    if [ "$EXTERNAL_IP" == "$NAT_IP" ]; then
        success "Outbound traffic uses NAT instance IP: $NAT_IP"
    else
        info "Outbound traffic IP: $EXTERNAL_IP (NAT IP: $NAT_IP)"
    fi
    
    # Test 7: Verify EKS nodes are in private subnets
    echo ""
    info "Test 7: Verifying EKS nodes are in private subnets..."
    PRIVATE_SUBNETS=$(terraform -chdir=envs/$ENV/network output -json private_subnet_ids 2>/dev/null | jq -r '.[]' || echo "")
    INSTANCE_ID=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].spec.providerID' | cut -d'/' -f5 || echo "")
    if [ -n "$INSTANCE_ID" ]; then
        NODE_SUBNET=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].SubnetId' --output text 2>/dev/null || echo "")
        if [ -n "$NODE_SUBNET" ] && echo "$PRIVATE_SUBNETS" | grep -q "$NODE_SUBNET"; then
            success "EKS nodes are in private subnets (subnet: $NODE_SUBNET)"
        else
            info "Node subnet: $NODE_SUBNET (checking against private subnets)"
        fi
    else
        info "Could not determine node subnet"
    fi
    
    # Cleanup test pod
    info "Cleaning up test pod..."
    kubectl delete pod network-test --grace-period=0 --force >/dev/null 2>&1 || true
else
    error "Test pod not ready (timeout)"
    kubectl delete pod network-test --force --grace-period=0 >/dev/null 2>&1 || true
    info "Skipping connectivity tests"
fi

# 7. IAM Roles for Service Accounts (IRSA)
section "7. IRSA Verification"

info "Checking ExternalDNS IAM role..."
EXTERNAL_DNS_ROLE=$(terraform -chdir=envs/$ENV/dns output -raw external_dns_role_arn 2>/dev/null)
if [ -n "$EXTERNAL_DNS_ROLE" ]; then
    success "ExternalDNS role: $EXTERNAL_DNS_ROLE"
else
    error "ExternalDNS role not found"
fi

info "Checking ALB Controller IAM role..."
ALB_ROLE=$(terraform -chdir=envs/$ENV/eks output -raw alb_controller_role_arn 2>/dev/null)
if [ -n "$ALB_ROLE" ]; then
    success "ALB Controller role: $ALB_ROLE"
else
    error "ALB Controller role not found"
fi

# Summary
section "Verification Complete!"

echo ""
info "Next steps:"
echo ""
echo "1. Generate access guide:"
echo "   make access-guide"
echo ""
echo "2. Generate SSM aliases:"
echo "   make ssm-aliases"
echo "   source ~/.ssm-aliases"
echo ""
echo "3. Access services:"
echo "   gitlab-web   # Opens GitLab at http://localhost:8443"
echo "   jenkins-web  # Opens Jenkins at http://localhost:8080"
echo ""
echo "4. Deploy Kubernetes controllers (see INFRASTRUCTURE_ACCESS.md after step 1)"
echo ""
