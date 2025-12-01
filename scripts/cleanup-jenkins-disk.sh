#!/bin/bash
set -e

# Environment parameter (default to dev)
ENV="${1:-dev}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${YELLOW}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

JENKINS_ID=$(terraform -chdir=envs/$ENV/cicd output -raw jenkins_server_id 2>/dev/null)

if [ -z "$JENKINS_ID" ]; then
    error "Could not get Jenkins server instance ID"
    exit 1
fi

info "Jenkins Server: $JENKINS_ID"
echo ""

# Check current disk usage
info "Current disk usage..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["df -h / /tmp /var/lib/docker && echo --- && docker system df"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
info "Finding largest directories in Jenkins home..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker exec jenkins du -sh /var/jenkins_home/* 2>/dev/null | sort -h | tail -10 || echo \"Could not access Jenkins home\""]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
read -p "Do you want to clean up Docker resources? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Cleaning Docker images, containers, volumes, and build cache..."
    CMD_ID=$(aws ssm send-command \
        --instance-ids "$JENKINS_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["docker system prune -af --volumes && echo --- && df -h / /tmp /var/lib/docker"]' \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)
    
    info "Waiting for cleanup to complete (this may take a minute)..."
    sleep 10
    
    OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$JENKINS_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null)
    
    echo "$OUTPUT"
    
    if echo "$OUTPUT" | grep -q "Total reclaimed space"; then
        RECLAIMED=$(echo "$OUTPUT" | grep "Total reclaimed space" | awk '{print $4, $5}')
        success "Reclaimed: $RECLAIMED"
    fi
fi

echo ""
read -p "Do you want to clean Jenkins workspace directories? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Cleaning Jenkins workspaces..."
    CMD_ID=$(aws ssm send-command \
        --instance-ids "$JENKINS_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["docker exec jenkins bash -c \"rm -rf /var/jenkins_home/workspace/* && du -sh /var/jenkins_home/workspace\" && echo --- && df -h /tmp"]' \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)
    sleep 5
    aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$JENKINS_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null
fi

echo ""
read -p "Do you want to clean Jenkins build logs? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Cleaning old Jenkins build logs..."
    CMD_ID=$(aws ssm send-command \
        --instance-ids "$JENKINS_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["docker exec jenkins bash -c \"find /var/jenkins_home/jobs -name builds -type d -exec du -sh {} \\; | sort -h | tail -5\" && echo \"---Cleaning logs older than 7 days---\" && docker exec jenkins bash -c \"find /var/jenkins_home/jobs -type f -name log -mtime +7 -delete && find /var/jenkins_home/logs -type f -mtime +7 -delete\" && df -h /tmp"]' \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)
    sleep 5
    aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$JENKINS_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null
fi

echo ""
info "Final disk usage:"
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["df -h / /tmp /var/lib/docker"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
success "Cleanup complete!"
echo ""
info "Alternative: Increase disk threshold in Jenkins UI:"
echo "  Manage Jenkins → Nodes → Configure Monitors → Free Disk Space"
echo "  Change threshold from 1GB to 500MB or lower"
