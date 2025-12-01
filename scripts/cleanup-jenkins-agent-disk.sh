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

# Get first Jenkins agent instance
JENKINS_AGENT_ID=$(terraform -chdir=envs/$ENV/cicd output -json jenkins_agent_ids 2>/dev/null | jq -r 'to_entries[0].value' 2>/dev/null)

if [ -z "$JENKINS_AGENT_ID" ] || [ "$JENKINS_AGENT_ID" == "null" ]; then
    info "Trying to find Jenkins agent via AWS CLI..."
    JENKINS_AGENT_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*jenkins-agent*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
fi

if [ -z "$JENKINS_AGENT_ID" ] || [ "$JENKINS_AGENT_ID" == "None" ]; then
    error "Could not find Jenkins agent instance"
    exit 1
fi

info "Jenkins Agent: $JENKINS_AGENT_ID"
echo ""

# Check current disk usage
info "Current disk usage on agent..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["df -h / /tmp /var && echo --- && docker system df"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
info "Finding largest directories..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["du -sh /var/lib/docker /opt/* /tmp/* 2>/dev/null | sort -h | tail -10"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
info "Checking agent workspace size..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker exec jenkins-agent-docker du -sh /home/jenkins/agent/* 2>/dev/null | sort -h || echo \"Could not access agent workspace\""]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
info "Cleaning Docker resources (images, containers, build cache)..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker system prune -af --volumes && echo --- && df -h / /tmp"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)

info "Waiting for cleanup (this may take 30-60 seconds)..."
sleep 15

OUTPUT=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "Total reclaimed space"; then
    RECLAIMED=$(echo "$OUTPUT" | grep "Total reclaimed space" | awk '{print $4, $5}')
    success "Reclaimed: $RECLAIMED"
fi

echo ""
read -p "Clean agent workspaces? This removes build artifacts (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Cleaning agent workspaces..."
    CMD_ID=$(aws ssm send-command \
        --instance-ids "$JENKINS_AGENT_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["docker exec jenkins-agent-docker bash -c \"rm -rf /home/jenkins/agent/workspace/* && du -sh /home/jenkins/agent\" && df -h /"]' \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)
    sleep 5
    aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$JENKINS_AGENT_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null
fi

echo ""
info "Final disk usage:"
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["df -h / /tmp && echo --- && docker system df"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

echo ""
success "Agent cleanup complete!"
echo ""
info "To increase agent disk permanently, update Terraform:"
echo "  envs/dev/cicd/cicd.auto.tfvars → jenkins_agent_volume_size_gb = 20"
echo "  Then: cd envs/dev/cicd && terragrunt apply"
