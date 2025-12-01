#!/bin/bash
set -e

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
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

section "Create New Terraform Environment"

# Check if environment name is provided
if [ -z "$1" ]; then
    error "Usage: $0 <environment-name> [vpc-cidr]"
    echo ""
    echo "Examples:"
    echo "  $0 staging"
    echo "  $0 staging 15.10.0.0/16"
    echo "  $0 prod 20.10.0.0/16"
    exit 1
fi

NEW_ENV=$1
VPC_CIDR=${2:-"15.10.0.0/16"}  # Default CIDR if not provided

# Check if environment already exists
if [ -d "envs/$NEW_ENV" ]; then
    error "Environment '$NEW_ENV' already exists in envs/$NEW_ENV"
    exit 1
fi

# Verify _shared directory exists
if [ ! -d "envs/_shared" ]; then
    error "_shared directory not found. Please ensure project structure is correct."
    exit 1
fi

info "Creating new environment: $NEW_ENV"
info "VPC CIDR: $VPC_CIDR"
echo ""

# Step 1: Create directory structure
section "Step 1: Creating Directory Structure"
mkdir -p envs/$NEW_ENV/{network,cicd,dns,eks}
success "Created directories for $NEW_ENV"

# Step 2: Create symlinks for each stack
section "Step 2: Creating Symlinks to Shared Configurations"

STACKS=("network" "cicd" "dns" "eks")

for stack in "${STACKS[@]}"; do
    info "Creating symlinks for $stack..."
    cd envs/$NEW_ENV/$stack
    
    # Create symlinks for all .tf files in _shared
    for tf_file in ../../_shared/$stack/*.tf; do
        if [ -f "$tf_file" ]; then
            ln -s "$tf_file" .
        fi
    done
    
    cd ../../..
    success "Symlinks created for $stack"
done

# Step 3: Create environment-specific variable files
section "Step 3: Creating Environment-Specific Variable Files"

# Create common variables file
info "Creating ${NEW_ENV}-common.tfvars..."
cat > envs/$NEW_ENV/${NEW_ENV}-common.tfvars <<EOF
# Common variables for $NEW_ENV environment
project_name = "proj"
env          = "$NEW_ENV"
region       = "eu-central-1"
EOF
success "Created ${NEW_ENV}-common.tfvars"

# Check if dev environment exists to copy from
if [ -d "envs/dev" ]; then
    info "Copying and customizing .tfvars files from dev environment..."
    
    # Network
    if [ -f "envs/dev/network/network.auto.tfvars" ]; then
        cp envs/dev/network/network.auto.tfvars envs/$NEW_ENV/network/
        # Update VPC CIDR in the new file
        sed -i '' "s|vpc_cidr *= *\"[^\"]*\"|vpc_cidr = \"$VPC_CIDR\"|g" envs/$NEW_ENV/network/network.auto.tfvars
        success "Created network.auto.tfvars with CIDR: $VPC_CIDR"
    fi
    
    # CICD
    if [ -f "envs/dev/cicd/cicd.auto.tfvars" ]; then
        cp envs/dev/cicd/cicd.auto.tfvars envs/$NEW_ENV/cicd/
        success "Created cicd.auto.tfvars"
    fi
    
    # DNS
    if [ -f "envs/dev/dns/dns.auto.tfvars" ]; then
        cp envs/dev/dns/dns.auto.tfvars envs/$NEW_ENV/dns/
        success "Created dns.auto.tfvars"
    fi
    
    # EKS
    if [ -f "envs/dev/eks/eks.auto.tfvars" ]; then
        cp envs/dev/eks/eks.auto.tfvars envs/$NEW_ENV/eks/
        success "Created eks.auto.tfvars"
    fi
else
    error "Dev environment not found. You'll need to create .tfvars files manually."
fi

# Step 4: Display summary and next steps
section "Step 4: Environment Created Successfully!"

success "Environment '$NEW_ENV' has been created!"
echo ""
echo -e "${CYAN}Directory Structure:${NC}"
echo "envs/$NEW_ENV/"
echo "  ├── ${NEW_ENV}-common.tfvars"
echo "  ├── network/"
echo "  │   ├── *.tf -> ../../_shared/network/*.tf (symlinks)"
echo "  │   └── network.auto.tfvars"
echo "  ├── cicd/"
echo "  │   ├── *.tf -> ../../_shared/cicd/*.tf (symlinks)"
echo "  │   └── cicd.auto.tfvars"
echo "  ├── dns/"
echo "  │   ├── *.tf -> ../../_shared/dns/*.tf (symlinks)"
echo "  │   └── dns.auto.tfvars"
echo "  └── eks/"
echo "      ├── *.tf -> ../../_shared/eks/*.tf (symlinks)"
echo "      └── eks.auto.tfvars"
echo ""

echo -e "${YELLOW}⚠ Next Steps:${NC}"
echo ""
echo "1. Review and customize variable files for $NEW_ENV:"
echo "   - envs/$NEW_ENV/network/network.auto.tfvars"
echo "   - envs/$NEW_ENV/cicd/cicd.auto.tfvars"
echo "   - envs/$NEW_ENV/dns/dns.auto.tfvars"
echo "   - envs/$NEW_ENV/eks/eks.auto.tfvars"
echo ""
echo "2. Update Makefile to recognize the new environment:"
echo "   Add '$NEW_ENV' to the STACKS logic"
echo ""
echo "3. Initialize and deploy:"
echo "   make init ENV=$NEW_ENV"
echo "   make apply STACK=network ENV=$NEW_ENV"
echo "   make apply STACK=cicd ENV=$NEW_ENV"
echo "   make apply STACK=eks ENV=$NEW_ENV"
echo "   make apply STACK=dns ENV=$NEW_ENV"
echo ""
echo "4. Generate access tools:"
echo "   make access-guide ENV=$NEW_ENV"
echo "   make ssm-aliases ENV=$NEW_ENV"
echo ""

info "Happy deploying! 🚀"
