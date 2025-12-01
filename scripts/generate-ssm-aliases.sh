#!/bin/bash
set -e

# Generate SSM port-forward aliases
ENV="${1:-dev}"  # Default to dev if no argument provided
OUTPUT_FILE="$HOME/.ssm-aliases-$ENV"

echo "Generating SSM port-forward aliases for environment: $ENV"

# Get instance IDs from Terraform
GITLAB_ID=$(terraform -chdir=envs/$ENV/cicd output -raw gitlab_server_id 2>/dev/null)
JENKINS_ID=$(terraform -chdir=envs/$ENV/cicd output -raw jenkins_server_id 2>/dev/null)
NAT_ID=$(terraform -chdir=envs/$ENV/network output -raw nat_instance_id 2>/dev/null)

cat > "$OUTPUT_FILE" <<EOF
# SSM Port-Forward Aliases ($ENV) - Generated on $(date)
# Add this to your ~/.zshrc or ~/.bashrc: source $OUTPUT_FILE

# GitLab Web UI (http://localhost:8443)
alias ssm-gitlab='aws ssm start-session --target ${GITLAB_ID} --document-name AWS-StartPortForwardingSession --parameters "{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8443\"]}"'
alias ssm-gitlab-bg='aws ssm start-session --target ${GITLAB_ID} --document-name AWS-StartPortForwardingSession --parameters "{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8443\"]}" > /dev/null 2>&1 &'

# Jenkins Web UI (http://localhost:8080)
alias ssm-jenkins='aws ssm start-session --target ${JENKINS_ID} --document-name AWS-StartPortForwardingSession --parameters "{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}"'
alias ssm-jenkins-bg='aws ssm start-session --target ${JENKINS_ID} --document-name AWS-StartPortForwardingSession --parameters "{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}" > /dev/null 2>&1 &'

# Jenkins Secret Server (http://localhost:18081)
alias ssm-jenkins-secrets='aws ssm start-session --target ${JENKINS_ID} --document-name AWS-StartPortForwardingSession --parameters "{\"portNumber\":[\"8081\"],\"localPortNumber\":[\"18081\"]}"'

# SSM Shell Sessions
alias ssm-gitlab-shell='aws ssm start-session --target ${GITLAB_ID}'
alias ssm-jenkins-shell='aws ssm start-session --target ${JENKINS_ID}'
alias ssm-nat-shell='aws ssm start-session --target ${NAT_ID}'

# Shortcuts
alias gitlab-web='ssm-gitlab'
alias gitlab-web-bg='ssm-gitlab-bg'
alias jenkins-web='ssm-jenkins'
alias jenkins-web-bg='ssm-jenkins-bg'

# Stop background SSM sessions
alias ssm-stop='killall session-manager-plugin 2>/dev/null || echo "No SSM sessions running"'
EOF

echo "✓ Aliases generated: $OUTPUT_FILE"
echo ""
echo "To use these aliases, add to your ~/.zshrc:"
echo "  source $OUTPUT_FILE"
echo ""
echo "Then reload your shell:"
echo "  source ~/.zshrc"
echo ""
echo "Usage examples:"
echo "  ./scripts/generate-ssm-aliases.sh         # Generate for dev (default)"
echo "  ./scripts/generate-ssm-aliases.sh prod    # Generate for prod"
echo "  ./scripts/generate-ssm-aliases.sh staging # Generate for staging"
echo ""
echo "Available aliases:"
echo "  ssm-gitlab        - Port-forward GitLab web UI to localhost:8443"
echo "  ssm-gitlab-bg     - Same as above, but runs in background"
echo "  ssm-jenkins       - Port-forward Jenkins web UI to localhost:8080"
echo "  ssm-jenkins-bg    - Same as above, but runs in background"
echo "  ssm-jenkins-secrets - Port-forward Jenkins secret server to localhost:18081"
echo "  ssm-gitlab-shell  - Open shell session on GitLab server"
echo "  ssm-jenkins-shell - Open shell session on Jenkins server"
echo "  ssm-nat-shell     - Open shell session on NAT instance"
echo "  gitlab-web        - Shortcut for ssm-gitlab"
echo "  gitlab-web-bg     - Shortcut for ssm-gitlab-bg"
echo "  jenkins-web       - Shortcut for ssm-jenkins"
echo "  jenkins-web-bg    - Shortcut for ssm-jenkins-bg"
echo "  ssm-stop          - Stop all background SSM sessions"
echo ""
