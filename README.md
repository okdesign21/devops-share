# 🏗️ AWS Infrastructure with Terraform

Multi-stack Terraform infrastructure for development and production environments.

## 📋 **Quick Start**

### **Prerequisites**
- Terraform ≥ 1.5
- AWS CLI v2 configured & credentials allowing required AWS services
- Access to S3 backend bucket: `tfstate-inf-orinbar-euc1` (already created)
- Cloudflare zone (e.g. `infinity.ortflix.uk`) + API token with DNS write permissions
- IAM group `Devs` exists (SSM access policy attaches automatically)
- Optional: Pre-baked AMIs tagged `type=jenkins` and `type=gitlab` (else leave AMI vars empty)

### **Provisioning Order (Dev)**
Order matters due to remote state dependencies:
1. `network` (provides VPC, subnets, SSM profile, NAT)
2. `cicd` (needs private subnet IDs & SSM profile)
3. `eks` (needs VPC subnets; creates OIDC provider & IRSA roles)
4. `dns` (needs CICD private IPs for A records + EKS OIDC provider ARN)

### **Deployment**
```bash
# Initialize all stacks
make init ENV=dev

# Deploy all stacks in order
make apply STACK=network ENV=dev
make apply STACK=cicd ENV=dev
make apply STACK=eks ENV=dev
make apply STACK=dns ENV=dev

# Generate access guide and SSM aliases for dev
make access-guide ENV=dev
make ssm-aliases ENV=dev
source ~/.ssm-aliases-dev

# Verify infrastructure
./scripts/verify-infrastructure.sh
```

### **Destroy**
Destroy in strict reverse dependency order:
```bash
# Destroy in reverse order
make destroy STACK=dns ENV=dev
make destroy STACK=eks ENV=dev
make destroy STACK=cicd ENV=dev
make destroy STACK=network ENV=dev

# Note: Cleanup script automatically runs after destroy
# to remove any orphaned IAM resources (roles, instance profiles)
# that may fail to delete due to AWS eventual consistency
```

### **Handling Orphaned IAM Resources**
If you encounter `EntityAlreadyExists` errors after a destroy/recreate cycle:
```bash
# The destroy process now automatically cleans up orphaned IAM resources
# But if you need to manually import them:
cd envs/dev/eks
terraform import -var-file=../dev-common.tfvars aws_iam_role.cluster proj-dev-eks-cluster-role
terraform import -var-file=../dev-common.tfvars aws_iam_role.node proj-dev-eks-node-role
terraform import -var-file=../dev-common.tfvars aws_iam_instance_profile.node_profile proj-dev-eks-node-profile
```

---

## 🏗️ **Stack Overview**

### **Project Structure**
```
envs/
├── _shared/              # Single source of truth for Terraform code
│   ├── network/         # Network stack configuration
│   ├── cicd/            # CICD stack configuration
│   ├── dns/             # DNS stack configuration
│   └── eks/             # EKS stack configuration
├── dev/                 # Development environment
│   ├── network/
│   │   ├── *.tf -> ../../_shared/network/*.tf  # Symlinks to shared config
│   │   └── network.auto.tfvars                 # Dev-specific variables
│   ├── cicd/
│   ├── dns/
│   └── eks/
└── prod/                # Production environment (same structure)
```

**Key Design:**
- **Zero code duplication**: All `.tf` files live in `envs/_shared/`
- **Environment-specific values**: Controlled via `.tfvars` files in each env
- **Separate state files**: Each env/stack maintains isolated Terraform state
- **Symlink-based**: Environments use symlinks pointing to shared configurations

### **1. Network** (`envs/_shared/network/`)
- VPC with public/private subnets
- Custom NAT instance (cost-optimized)
- SSM access configuration
- Security groups

### **2. CICD** (`envs/_shared/cicd/`)
- GitLab server (version control)
- Jenkins server (build automation)
- Jenkins agents (ephemeral builders)
- SSM-only access (no public IPs)

### **3. DNS** (`envs/_shared/dns/`)
- Route53 public zone (delegated from Cloudflare)
- Route53 private zone (`vpc.internal`)
- ACM certificate with DNS validation
- ExternalDNS IRSA role

### **4. EKS** (`envs/_shared/eks/`)
- EKS cluster with managed node groups
- AWS Load Balancer Controller IRSA
- Public API (restricted IPs)
- Private worker nodes

---

## 🔐 **Access & Security Model**

- All CICD instances are in private subnets (no public IPs).
- Access via AWS Systems Manager (SSM) Session Manager port-forwarding.
- Security group model: SSM-only SG for Jenkins/GitLab, internal VPC communication allowed.
- Policy restricts SSM start-session by tags (`Project`, `Environment`).
- EKS API public access is IP-restricted (`home_ip`, `lab_ip`, plus NAT instance /32).
- Cloudflare → Route53 delegation only created automatically for `env == dev`.

### **Quick Access (Using Aliases)**
```bash
# Generate aliases for specific environment
make ssm-aliases ENV=dev
source ~/.ssm-aliases-dev

# Or for production
make ssm-aliases ENV=prod
source ~/.ssm-aliases-prod

# Use simple commands
gitlab-web        # Opens GitLab at http://localhost:8443
jenkins-web       # Opens Jenkins at http://localhost:8080
ssm-gitlab-shell  # SSH into GitLab server
ssm-jenkins-shell # SSH into Jenkins server
```

### **Manual SSM Port-Forward (if needed)**
```bash
# GitLab (forward container HTTPS -> local 8443)
aws ssm start-session --target <gitlab_instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8443"]}'

# Jenkins (forward server 8080 -> local 8080)
aws ssm start-session --target <jenkins_instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

### **Kubernetes Cluster**
```bash
# Update kubeconfig
aws eks update-kubeconfig --name proj-dev-cluster --region eu-central-1

# Or use terraform output
$(terraform -chdir=envs/dev/eks output -raw kubeconfig_command)
```

---

## 🔧 **Make Commands**

```bash
make init ENV=dev           # Initialize Terraform backend
make plan ENV=dev           # Plan changes
make apply ENV=dev          # Apply infrastructure
make destroy ENV=dev        # Destroy infrastructure
make output ENV=dev         # Show outputs
make validate ENV=dev       # Validate configurations
make fmt ENV=dev            # Format Terraform files

# Helper commands
make access-guide           # Generate INFRASTRUCTURE_ACCESS.md
make ssm-aliases            # Generate shell aliases for SSM
```

---

## 🛠️ **Utility Scripts**

Located in `scripts/` directory. All scripts support environment parameter (defaults to `dev`).

### **Environment Management**
- **`create-new-env.sh <env-name> [vpc-cidr]`**: Automatically creates a new environment
  ```bash
  ./scripts/create-new-env.sh staging 15.10.0.0/16
  # Creates complete environment structure with symlinks and .tfvars
  ```

### **Access & Setup**
- **`generate-access-commands.sh [env]`**: Creates comprehensive access guide
  ```bash
  ./scripts/generate-access-commands.sh dev
  # Outputs: INFRASTRUCTURE_ACCESS_dev.md
  ```
  
- **`generate-ssm-aliases.sh [env]`**: Generates shell aliases for SSM
  ```bash
  ./scripts/generate-ssm-aliases.sh dev
  source ~/.ssm-aliases-dev
  gitlab-web  # Quick access to GitLab
  ```

### **Verification & Monitoring**
- **`verify-infrastructure.sh [env]`**: Validates all infrastructure components
  ```bash
  ./scripts/verify-infrastructure.sh dev
  ./scripts/verify-infrastructure.sh prod
  # Checks: VPC, NAT, CICD instances, EKS cluster, DNS, certificates
  ```

### **Maintenance**
- **`cleanup-jenkins-disk.sh [env]`**: Cleans Jenkins server disk space
  ```bash
  ./scripts/cleanup-jenkins-disk.sh dev
  # Shows current usage and cleans workspace, logs, Docker images
  ```

- **`cleanup-jenkins-agent-disk.sh [env]`**: Cleans Jenkins agent disk space
  ```bash
  ./scripts/cleanup-jenkins-agent-disk.sh dev
  ```

- **`cleanup-orphaned-iam.sh [env] [project] [region]`**: Cleans up orphaned IAM resources
  ```bash
  ./scripts/cleanup-orphaned-iam.sh dev proj eu-central-1
  # Removes IAM roles and instance profiles that survive terraform destroy
  # Automatically called after 'make destroy'
  ```

- **`debug-jenkins-agent.sh [env]`**: Comprehensive Jenkins agent diagnostics
  ```bash
  ./scripts/debug-jenkins-agent.sh dev
  # Checks agent connectivity, DNS resolution, Docker status, and logs
  ```

### **AMI Management**
- **`create-ami-snapshots.sh [env]`**: Creates AMI snapshots of Jenkins/GitLab servers
  ```bash
  ./scripts/create-ami-snapshots.sh dev
  # Interactive menu: Jenkins only, GitLab only, or both
  # Creates tagged AMIs for backup/reuse
  ```

---

## 🌍 **Managing Multiple Environments**

### **Creating a New Environment**
```bash
# Quick create with default CIDR
./scripts/create-new-env.sh staging

# Or specify custom VPC CIDR
./scripts/create-new-env.sh staging 15.10.0.0/16
```

This automatically:
- Creates directory structure with symlinks
- Copies and customizes `.tfvars` from dev
- Sets up proper environment variables

### **Deploying a New Environment**
```bash
# 1. Review and customize variables
vim envs/staging/network/network.auto.tfvars

# 2. Update Makefile (add staging to STACKS logic)

# 3. Deploy in order
make init ENV=staging
make apply STACK=network ENV=staging
make apply STACK=cicd ENV=staging
make apply STACK=eks ENV=staging
make apply STACK=dns ENV=staging

# 4. Generate access tools
make access-guide ENV=staging
make ssm-aliases ENV=staging
source ~/.ssm-aliases-staging
```

---

## 📚 **Documentation**

- **[ADDING_NEW_ENV.md](ADDING_NEW_ENV.md)**: Detailed guide for adding new environments
- **[INFRASTRUCTURE_ACCESS_*.md]**: Access guides per environment (auto-generated)
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Detailed architecture overview
- **[K8S_INTEGRATION.md](K8S_INTEGRATION.md)**: Kubernetes manifests and setup
- **[Makefile](Makefile)**: Available commands

### **Quick Script Reference**

| Script | Purpose | Usage |
|--------|---------|-------|
| `create-new-env.sh` | Create new environment | `./scripts/create-new-env.sh <env> [cidr]` |
| `generate-access-commands.sh` | Creates access documentation | `make access-guide ENV=<env>` |
| `generate-ssm-aliases.sh` | Creates shell aliases | `make ssm-aliases ENV=<env>` |
| `verify-infrastructure.sh` | Validates all components | `./scripts/verify-infrastructure.sh <env>` |
| `create-ami-snapshots.sh` | Creates CICD AMI backups | `./scripts/create-ami-snapshots.sh <env>` |
| `cleanup-jenkins-disk.sh` | Cleans Jenkins disk space | `./scripts/cleanup-jenkins-disk.sh` |
| `cleanup-jenkins-agent-disk.sh` | Cleans agent disk space | `./scripts/cleanup-jenkins-agent-disk.sh` |
| `cleanup-orphaned-iam.sh` | Removes orphaned IAM resources | `./scripts/cleanup-orphaned-iam.sh <env>` |
| `debug-jenkins-agent.sh` | Diagnoses agent issues | `./scripts/debug-jenkins-agent.sh` |

---

## 🚀 **Production Deployment**

Production environment structure is ready in `envs/prod/`. To populate:

1. Copy dev configurations to prod directories
2. Update CIDRs (use 20.10.x.x range)
3. Adjust instance sizes and counts
4. Deploy with `ENV=prod`

---

## 📝 **Maintenance & Scaling**

### **Regular Maintenance**
- **Disk Cleanup**: Run cleanup scripts when Jenkins disk usage is high
  ```bash
  ./scripts/cleanup-jenkins-disk.sh
  ./scripts/cleanup-jenkins-agent-disk.sh
  ```

- **Create AMI Snapshots**: Before major changes or regularly for backups
  ```bash
  ./scripts/create-ami-snapshots.sh
  ```

- **Debug Agent Issues**: When Jenkins agents fail to connect
  ```bash
  ./scripts/debug-jenkins-agent.sh
  ```

### **Scaling & Updates**
- Adjust node count: edit `desired_size` in `eks.auto.tfvars` then `make apply STACK=eks ENV=dev`
- Upgrade EKS: bump `cluster_version`, apply; addons upgrade automatically
- Rotate SSH key: destroy `network` stack (or remove key resources) and re-apply; new PEM written under `envs/dev/network/`
- NAT Cost: Custom NAT instance (~$7/mo t3.micro) vs AWS NAT Gateway (~$45+). Monitor bandwidth usage
- Provider upgrades: `terraform init -upgrade` inside each stack directory
- Certificate renewal: Automatic via ACM init -upgrade`
- Rotate SSH keys: Regenerate via `keygen.tf`
- Update EKS version: Change `cluster_version` variable
- Certificate renewal: Automatic via ACM

---

## ✅ **Status**

Dev environment workflow & docs complete. Production templates scaffolded; finalize CIDRs, instance sizing, and stricter IP allow list before marking prod ready.

**Status: Dev Ready / Prod Configurable**

For detailed architecture explanations, see [ARCHITECTURE.md](ARCHITECTURE.md).
### **Scaling & Updates**
- Adjust node count: edit `desired_size` in `eks.auto.tfvars` then `make apply STACK=eks ENV=dev`
- Upgrade EKS: bump `cluster_version`, apply; addons upgrade automatically
- Rotate SSH key: destroy `network` stack (or remove key resources) and re-apply
- Provider upgrades: `terraform init -upgrade` inside each stack directory

---

## 🔧 **Configuration**

### **Variable Management**
Layered configuration using:
- `envs/dev/dev-common.tfvars` - Shared settings
- `envs/dev/*/*.auto.tfvars` - Stack-specific overrides

### **Cloudflare Token**
```bash
export TF_VAR_cloudflare_api_token="<your_token>"
```
Or add to `envs/dev/dns/secrets.auto.tfvars` (don't commit)

### **AMI Resolution**
Leave AMI vars empty to auto-lookup by tag `type=jenkins|gitlab`, or specify explicit AMI IDs.

**See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical architecture.**

---

## ✅ **Status**

**Dev: Ready for Production Use** ✅  
**Prod: Templates Ready** (configure CIDRs and sizing)

For architecture details, design decisions, and technical deep-dives, see [ARCHITECTURE.md](ARCHITECTURE.md).