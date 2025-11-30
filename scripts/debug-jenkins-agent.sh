#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

section() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================${NC}"
}

info() { echo -e "${YELLOW}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Get instance IDs
JENKINS_ID=$(terraform -chdir=envs/dev/cicd output -raw jenkins_server_id 2>/dev/null)

if [ -z "$JENKINS_ID" ]; then
    error "Could not get Jenkins server instance ID"
    exit 1
fi

# Get first Jenkins agent instance (agents are deployed via for_each)
JENKINS_AGENT_ID=$(terraform -chdir=envs/dev/cicd output -json jenkins_agent_ids 2>/dev/null | jq -r 'to_entries[0].value' 2>/dev/null)

if [ -z "$JENKINS_AGENT_ID" ] || [ "$JENKINS_AGENT_ID" == "null" ]; then
    info "Trying to find Jenkins agent via AWS CLI..."
    PROJECT_NAME=$(terraform -chdir=envs/dev/cicd output -json 2>/dev/null | jq -r '.jenkins_server_id.value' | grep -oE '^i-[a-z0-9]+' || echo "")
    JENKINS_AGENT_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*jenkins-agent*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
fi

if [ -z "$JENKINS_AGENT_ID" ] || [ "$JENKINS_AGENT_ID" == "None" ]; then
    error "Could not find Jenkins agent instance ID"
    error "Make sure the agent is deployed: check envs/dev/cicd/cicd.auto.tfvars for jenkins_agent_count"
    exit 1
fi

section "1. Jenkins Server Diagnostics"

info "Instance: $JENKINS_ID"

# Check containers
info "Checking containers..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker ps -a --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\""]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

# Check secret file
info "Checking agent secret file..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ls -lh /opt/jenkins/agent-secrets/; echo ---; if [ -f /opt/jenkins/agent-secrets/docker-secret.txt ]; then echo \"Secret exists ($(wc -c < /opt/jenkins/agent-secrets/docker-secret.txt) bytes)\"; else echo \"Secret file missing\"; fi"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

# Check readiness markers
info "Checking readiness markers..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ls -lh /opt/jenkins/agent-secrets/*.{txt,ready,timeout} 2>/dev/null || echo \"No markers yet\""]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

# Check Jenkins logs (last 50 lines)
info "Jenkins container logs (last 50 lines)..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker logs --tail 50 jenkins 2>&1 | grep -E \"(Agent|docker|secret|ready|JNLP|inbound)\" || docker logs --tail 30 jenkins 2>&1"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

section "2. Jenkins Agent Diagnostics"

info "Instance: $JENKINS_AGENT_ID"

# Check containers
info "Checking agent container..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker ps -a --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\""]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

# Check .env file
info "Checking agent .env file..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["if [ -f /opt/jenkins-agent/.env ]; then echo \"=== .env exists ===\"  && cat /opt/jenkins-agent/.env | sed \"s/JENKINS_SECRET=.*/JENKINS_SECRET=***REDACTED***/\"; else echo \".env file missing\"; fi"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

# Check agent logs (last 100 lines)
info "Agent container logs (last 100 lines)..."
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["docker logs --tail 100 jenkins-agent-docker 2>&1"]' \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

# Check network connectivity
info "Testing connectivity from agent to server..."
JENKINS_IP=$(terraform -chdir=envs/dev/cicd output -raw jenkins_private_ip 2>/dev/null)
CMD_ID=$(aws ssm send-command \
    --instance-ids "$JENKINS_AGENT_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"echo 'Testing jenkins-server.vpc.internal:8080...' && timeout 5 nc -zv jenkins-server.vpc.internal 8080 2>&1; echo 'Testing $JENKINS_IP:8080...' && timeout 5 nc -zv $JENKINS_IP 8080 2>&1; echo 'Testing secret server 8081...' && timeout 5 nc -zv jenkins-server.vpc.internal 8081 2>&1\"]" \
    --output text \
    --query 'Command.CommandId' 2>/dev/null)
sleep 3
aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$JENKINS_AGENT_ID" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null

section "3. Quick Fix Commands"

echo ""
info "If the secret is missing or stale, restart Jenkins server:"
echo "  aws ssm send-command --instance-ids $JENKINS_ID --document-name AWS-RunShellScript --parameters 'commands=[\"cd /opt/jenkins && docker compose restart\"]'"
echo ""
info "If agent can't connect, restart agent:"
echo "  aws ssm send-command --instance-ids $JENKINS_AGENT_ID --document-name AWS-RunShellScript --parameters 'commands=[\"cd /opt/jenkins-agent && docker compose restart\"]'"
echo ""
info "To force re-fetch secret and restart agent:"
echo "  aws ssm send-command --instance-ids $JENKINS_AGENT_ID --document-name AWS-RunShellScript --parameters 'commands=[\"cd /opt/jenkins-agent && docker compose down && bash /usr/local/bin/jenkins-agent-init.sh\"]'"
echo ""
