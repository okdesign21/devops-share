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
section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROJECT_NAME=$(terraform -chdir=envs/$ENV/network output -raw vpc_id 2>/dev/null | grep -oE 'vpc-[a-z0-9]+' | head -1 || echo "devops")

section "AWS AMI Creation Tool (Environment: $ENV)"

echo ""
info "Getting instance information..."

JENKINS_ID=$(terraform -chdir=envs/$ENV/cicd output -raw jenkins_server_id 2>/dev/null)
GITLAB_ID=$(terraform -chdir=envs/$ENV/cicd output -raw gitlab_server_id 2>/dev/null)

if [ -z "$JENKINS_ID" ]; then
    error "Could not get Jenkins instance ID"
    exit 1
fi

if [ -z "$GITLAB_ID" ]; then
    error "Could not get GitLab instance ID"
    exit 1
fi

echo ""
info "Found instances:"
echo "  Jenkins: $JENKINS_ID"
echo "  GitLab:  $GITLAB_ID"
echo ""

# Show menu
echo "Select which AMI(s) to create:"
echo ""
echo "  1) Jenkins only"
echo "  2) GitLab only"
echo "  3) Both Jenkins and GitLab"
echo "  4) Cancel"
echo ""
read -p "Enter choice [1-4]: " choice

create_jenkins=false
create_gitlab=false

case $choice in
    1)
        create_jenkins=true
        ;;
    2)
        create_gitlab=true
        ;;
    3)
        create_jenkins=true
        create_gitlab=true
        ;;
    4)
        info "Cancelled."
        exit 0
        ;;
    *)
        error "Invalid choice"
        exit 1
        ;;
esac

echo ""
read -p "Add custom tag/suffix? (leave empty for timestamp only): " CUSTOM_TAG

if [ -n "$CUSTOM_TAG" ]; then
    TAG_SUFFIX="${CUSTOM_TAG}-${TIMESTAMP}"
else
    TAG_SUFFIX="$TIMESTAMP"
fi

echo ""
info "AMI images will be tagged with suffix: $TAG_SUFFIX"
echo ""

# Function to create AMI
create_ami() {
    local INSTANCE_ID=$1
    local SERVICE_NAME=$2
    local AMI_NAME="${SERVICE_NAME}-${TAG_SUFFIX}"
    local AMI_DESCRIPTION="${SERVICE_NAME} server snapshot - created on $(date '+%Y-%m-%d %H:%M:%S')"
    
    section "Creating ${SERVICE_NAME} AMI"
    
    info "Preparing instance (stopping containers for clean snapshot)..."
    
    # Optional: Stop containers for clean snapshot
    read -p "Stop ${SERVICE_NAME} containers before snapshot? (recommended) (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        info "Stopping containers on $INSTANCE_ID..."
        CMD_ID=$(aws ssm send-command \
            --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["docker ps -q | xargs -r docker stop"]' \
            --output text \
            --query 'Command.CommandId' 2>/dev/null)
        
        sleep 5
        
        STATUS=$(aws ssm get-command-invocation \
            --command-id "$CMD_ID" \
            --instance-id "$INSTANCE_ID" \
            --query 'Status' \
            --output text 2>/dev/null)
        
        if [ "$STATUS" == "Success" ]; then
            success "Containers stopped"
        else
            info "⚠️  Could not confirm containers stopped (Status: $STATUS)"
        fi
        
        sleep 2
    fi
    
    info "Creating AMI: $AMI_NAME"
    
    AMI_ID=$(aws ec2 create-image \
        --instance-id "$INSTANCE_ID" \
        --name "$AMI_NAME" \
        --description "$AMI_DESCRIPTION" \
        --no-reboot \
        --tag-specifications \
            "ResourceType=image,Tags=[\
{Key=Name,Value=$SERVICE_NAME},\
{Key=Type,Value=$SERVICE_NAME},\
{Key=Environment,Value=dev},\
{Key=CreatedBy,Value=ami-snapshot-script},\
{Key=CreatedAt,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)},\
{Key=SourceInstance,Value=$INSTANCE_ID}\
]" \
        --output text \
        --query 'ImageId' 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$AMI_ID" ]; then
        success "AMI creation initiated: $AMI_ID"
        echo ""
        info "AMI Details:"
        echo "  Name:        $AMI_NAME"
        echo "  AMI ID:      $AMI_ID"
        echo "  Type:     $SERVICE_NAME"
        echo "  Source:      $INSTANCE_ID"
        echo ""
        
        # Restart containers if we stopped them
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            info "Restarting containers..."
            aws ssm send-command \
                --instance-ids "$INSTANCE_ID" \
                --document-name "AWS-RunShellScript" \
                --parameters 'commands=["cd /opt/'"${SERVICE_NAME,,}"' && docker compose up -d 2>/dev/null || cd /opt/'"${SERVICE_NAME,,}"'-agent && docker compose up -d 2>/dev/null || echo \"Could not find compose file\""]' \
                --output text \
                --query 'Command.CommandId' >/dev/null 2>&1
            success "Restart command sent"
        fi
        
        info "AMI creation in progress (this may take several minutes)"
        echo ""
    else
        error "Failed to create AMI for $SERVICE_NAME"
    fi
}

# Create AMIs
if [ "$create_jenkins" = true ]; then
    create_ami "$JENKINS_ID" "jenkins"
fi

if [ "$create_gitlab" = true ]; then
    create_ami "$GITLAB_ID" "gitlab"
fi

section "Summary"

echo ""
info "Listing recent AMIs..."
aws ec2 describe-images \
    --owners self \
    --filters "Name=tag:CreatedBy,Values=ami-snapshot-script" \
    --query 'sort_by(Images, &CreationDate)[-5:] | reverse(@) | [].[Name, ImageId, State, CreationDate]' \
    --output table

echo ""
success "AMI creation complete!"
echo ""
info "To use these AMIs in Terraform:"
echo ""
echo "  1. Update envs/dev/cicd/cicd.auto.tfvars:"
echo "     jenkins_custom_ami_id = \"ami-xxxxx\""
echo "     gitlab_custom_ami_id  = \"ami-xxxxx\""
echo ""
echo "  2. Apply changes:"
echo "     cd envs/dev/cicd"
echo "     terragrunt apply"
echo ""
info "To delete old AMIs:"
echo "  aws ec2 deregister-image --image-id ami-xxxxx"
echo ""
