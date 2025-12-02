# 🏗️ Infrastructure Architecture

## 📋 **Overview**

Multi-stack AWS infrastructure with Terraform for development and production environments:
- **Network**: VPC, subnets, NAT instance, SSM access
- **CICD**: GitLab & Jenkins (SSM-only, private DNS)
- **DNS**: Route53 public zone + private zone for internal service discovery
- **EKS**: Kubernetes cluster with ALB controller & ExternalDNS
- **Secrets**: Infisical-based secrets management with External Secrets Operator

### **Code Organization**
The infrastructure uses a **symlink-based structure** to eliminate code duplication:

```
devops-share/
├── .env                        # Sensitive credentials (gitignored)
├── .env.example               # Template for environment variables
├── envs/
│   ├── _shared/               # Single source of truth
│   │   ├── network/*.tf      # Shared network configuration
│   │   ├── cicd/*.tf         # Shared CICD configuration
│   │   ├── dns/*.tf          # Shared DNS configuration
│   │   └── eks/*.tf          # Shared EKS configuration
│   ├── dev/
│   │   ├── dev-common.tfvars # Environment config (non-sensitive)
│   │   ├── network/
│   │   │   ├── *.tf → ../../_shared/network/*.tf  # Symlinks
│   │   │   └── network.auto.tfvars                # Dev-specific values
│   │   └── (cicd, dns, eks with same pattern)
│   └── prod/
│       └── (same structure as dev)
└── Makefile                   # Orchestrates terraform with .env loading
```

**Benefits:**
- ✅ **DRY Principle**: Edit once in `_shared/`, applies to all environments
- ✅ **Isolated State**: Each env/stack has separate Terraform state files
- ✅ **Environment Control**: Variables in `.tfvars` customize behavior per env
- ✅ **Git-Friendly**: Symlinks are tracked and version-controlled

---

## 🌐 **Network Architecture**

### **VPC Structure**
```
VPC: 10.10.0.0/16 (dev) | 20.10.0.0/16 (prod)

Public Subnets (10.10.1.0/24, 10.10.2.0/24):
  - NAT instance (custom EC2-based NAT)
  - Internet Gateway

Private Subnets (10.10.11.0/24, 10.10.12.0/24):
  - CICD services (GitLab, Jenkins)
  - EKS worker nodes
  - All private resources
```

### **Security Model**
- **SSM-Only Access**: No bastion hosts, no SSH keys
- **Private Subnets**: All workloads in private subnets
- **Custom NAT**: Cost-effective t3.micro NAT instance
- **Security Groups**: Restrictive, minimal ingress rules

---

## 🔐 **CICD Infrastructure**

### **Services**
- **GitLab**: Version control, CI/CD pipelines (Docker Compose)
- **Jenkins**: Build automation, deployment orchestration (Docker Compose)
- **Jenkins Agents**: Ephemeral build executors (auto-registered via JCasC)

### **Auto-Configuration Features**
- **Jenkins URL**: Automatically set via JCasC to `http://jenkins-server.vpc.internal:8080`
- **Agent Registration**: Agents auto-register via JCasC configuration
- **Agent Secret Distribution**: Jenkins publishes agent secret via HTTP endpoint on port 8081
- **Plugin Installation**: Automatic installation of required plugins on startup
  - Configuration as Code (JCasC)
  - Docker Pipeline
  - Git Plugin
  - Pipeline Plugin (workflow-aggregator)
  - Slack Notification
  - Credentials

### **Access Pattern**
```bash
# Quick access using aliases (after running: make ssm-aliases)
gitlab-web        # Opens GitLab at http://localhost:8443
jenkins-web       # Opens Jenkins at http://localhost:8080
```

### **Internal Communication**
- **GitLab self-reference**: `http://localhost` (container → localhost)
- **Jenkins self-reference**: `http://localhost:8080` (container → localhost)
- **Jenkins → GitLab**: `http://gitlab-server.vpc.internal` (via private DNS)
- **Jenkins ← Agents**: `http://jenkins-server.vpc.internal:8080` (via private DNS)
- **Agent Secret Exchange**: `http://jenkins-server.vpc.internal:8081/docker-secret.txt` (via nginx sidecar)

### **Jenkins Agent Auto-Registration Flow**
1. Jenkins server starts → JCasC creates agent node named "docker"
2. Groovy init script extracts agent secret → writes to `/var/jenkins_home/agent-secrets/docker-secret.txt`
3. Nginx sidecar container serves secrets directory on port 8081
4. Agent EC2 instance fetches secret from `http://jenkins-server.vpc.internal:8081/docker-secret.txt`
5. Agent connects automatically using WebSocket protocol


---

## 🌍 **DNS Architecture**

### **Public DNS (Route53)**
```
Cloudflare: infinity.ortflix.uk
    ↓ (NS delegation)
Route53: r53.infinity.ortflix.uk
    ↓ (ExternalDNS)
Apps: app.dev.r53.infinity.ortflix.uk → ALB
      weather.dev.r53.infinity.ortflix.uk → ALB
```

### **Private DNS (Route53 Private Zone)**
```
Zone: vpc.internal (VPC-scoped)

Records:
  gitlab-server.vpc.internal  → 10.10.11.X
  jenkins-server.vpc.internal → 10.10.11.Y
```

**Purpose**: Clean hostname resolution for internal services (GitLab, Jenkins, ArgoCD)

---

## 🔐 **Secrets Management (Infisical + External Secrets Operator)**

### **Architecture Overview**
```
.env file (local)
  ↓ (loaded by Makefile)
Terraform Variables
  ↓ (creates K8s secret)
infisical-credentials secret (EKS)
  ↓ (referenced by)
ClusterSecretStore (External Secrets Operator)
  ↓ (fetches from)
Infisical API (eu.infisical.com)
  ↓ (creates)
ExternalSecret resources
  ↓ (populate)
Kubernetes Secrets → Pod Environment Variables
```

### **Components**

#### **1. Local .env File**
```bash
# Infisical Machine Identity credentials
TF_VAR_infisical_client_id="xxx"
TF_VAR_infisical_client_secret="xxx"

# Infisical project context
INFISICAL_PROJECT_ID="f1b25a9d-602f-4116-aaeb-4a5eff72cda2"

# Optional: Override auto-fetch
# TF_VAR_cloudflare_api_token="xxx"
```

**Security:**
- ✅ `.env` is gitignored (never committed)
- ✅ `.env.example` provides template
- ✅ `TF_VAR_*` prefix auto-loads into Terraform

#### **2. EKS Bootstrap Secret**
Terraform creates `infisical-credentials` secret in EKS cluster:

```hcl
# envs/dev/eks/main.tf
resource "kubernetes_secret" "infisical_credentials" {
  count = var.enable_infisical ? 1 : 0
  
  metadata {
    name      = "infisical-credentials"
    namespace = "default"
  }
  
  data = {
    "client-id"     = var.infisical_client_id
    "client-secret" = var.infisical_client_secret
  }
}
```

**Purpose:** Provides authentication for External Secrets Operator to fetch secrets from Infisical.

#### **3. ClusterSecretStore (ArgoCD)**
```yaml
# argocd_repo/charts/vendor/infisical-secretstore/
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: infisical-secret-store
spec:
  provider:
    infisical:
      auth:
        universalAuthCredentials:
          clientId:
            secretRef:
              name: infisical-credentials
              key: client-id
          clientSecret:
            secretRef:
              name: infisical-credentials
              key: client-secret
      secretsScope:
        projectSlug: "project-name"
```

**Deployment:** ArgoCD ApplicationSet deploys this to all clusters automatically.

#### **4. Application ExternalSecrets**
Each application defines what secrets it needs:

```yaml
# argocd_repo/charts/weather-app/templates/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "weather-app.fullname" . }}-secret
spec:
  secretStoreRef:
    name: infisical-secret-store
    kind: ClusterSecretStore
  target:
    name: {{ include "weather-app.fullname" . }}-secret
  dataFrom:
    - find:
        path: {{ .Values.externalSecrets.secretPath }}
        name:
          regexp: ".*"
```

**Result:** Kubernetes secret auto-populated from Infisical, mounted to pods.

### **Infisical CLI Integration**

#### **DNS Stack Auto-Fetch**
The Makefile automatically fetches `cloudflare_api_token` when applying DNS stack:

```makefile
apply:
	@for s in $(STACK_LIST) ; do \
		set -a; [ -f .env ] && . ./.env || true; set +a; \
		if [ "$$s" = "dns" ] && [ -z "$$TF_VAR_cloudflare_api_token" ]; then \
		  if command -v infisical >/dev/null 2>&1; then \
		    export TF_VAR_cloudflare_api_token="$$(infisical get -p "$${INFISICAL_PROJECT_ID}" -e "$(ENV)" cloudflare_api_token --plain)"; \
		  fi; \
		fi; \
		terraform -chdir=envs/$(ENV)/$$s apply -var-file=$(COMMON_VARS) || exit 1; \
	done
```

**Workflow:**
1. Makefile sources `.env` file (loads `INFISICAL_PROJECT_ID`)
2. If DNS stack + no manual token → run `infisical get`
3. Token injected as `TF_VAR_cloudflare_api_token` → Terraform uses it

**Install Infisical CLI:**
```bash
brew install infisical/get-cli/infisical
infisical login  # Authenticate
```

### **Secret Flow for Applications**

#### **Jenkins Pipeline Secrets**
```yaml
# ExternalSecret fetches from /jenkins path in Infisical
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: jenkins-pipeline-secrets
spec:
  dataFrom:
    - find:
        path: /jenkins
```

**Available to pods as:**
```yaml
envFrom:
  - secretRef:
      name: jenkins-pipeline-secrets
```

#### **Weather App Secrets**
```yaml
# Fetches from /weather-app/{env} path
values-backend-dev.yaml:
  externalSecrets:
    enabled: true
    secretPath: /weather-app/dev
```

**Secrets in Infisical:**
- `dev` environment: `/weather-app/dev` → `DATABASE_URL`, `API_KEY`
- `prod` environment: `/weather-app/prod` → different values

### **Security Benefits**

- ✅ **No secrets in Git**: `.env` and Terraform state contain references only
- ✅ **Centralized management**: All secrets in Infisical dashboard
- ✅ **Runtime fetching**: Apps fetch secrets at deployment time
- ✅ **Environment isolation**: Dev/staging/prod secrets separated
- ✅ **Automatic rotation**: Update in Infisical → ESO syncs to K8s
- ✅ **Audit trail**: Infisical logs all secret access

---

## ☸️ **Kubernetes (EKS)**

### **Cluster Configuration**
- **Node Groups**: Managed node groups in private subnets
- **Access**: Public API endpoint (restricted to admin IPs + NAT IP)
- **Version**: Latest stable EKS version
- **Add-ons**: VPC CNI, CoreDNS, kube-proxy

### **Controllers**
1. **AWS Load Balancer Controller** (IRSA)
   - Creates internet-facing ALBs for Ingress resources
   - Target type: IP (direct pod routing)

2. **ExternalDNS** (IRSA)
   - Automatically creates Route53 records
   - Domain filter: `r53.infinity.ortflix.uk`
   - TXT registry for ownership

### **Application Exposure**
```yaml
# App Service (ClusterIP)
Service → Ingress (ALB annotations) → ALB → Route53 (ExternalDNS)
```

**Result**: `https://app.dev.r53.infinity.ortflix.uk` → ALB → Pods

---

## 🔒 **Certificate Management**

### **ACM Certificate**
```
Primary: app.dev.r53.infinity.ortflix.uk
SANs:
  - *.dev.r53.infinity.ortflix.uk (wildcard)
  - weather.dev.r53.infinity.ortflix.uk
```

**Validation**: DNS validation via Route53 (automatic)  
**Usage**: Kubernetes Ingress annotations (ALB Controller)

---

## 📊 **Deployment Flow**

### **Infrastructure Deployment Order**

**Prerequisites:**
```bash
# 1. Create .env file from template
cp .env.example .env
# Edit .env with actual Infisical credentials

# 2. (Optional) Install Infisical CLI for auto-fetch
brew install infisical/get-cli/infisical
infisical login
```

**Deployment:**
```bash
1. Network Stack (VPC, subnets, NAT, SSM)
   make apply STACK=network ENV=dev

2. EKS Stack (cluster, nodes, IRSA roles, infisical-credentials secret)
   make apply STACK=eks ENV=dev
   # Requires: Network stack for VPC/subnets
   # Creates: infisical-credentials K8s secret for ESO

3. CICD Stack (GitLab, Jenkins instances)
   make apply STACK=cicd ENV=dev
   # Requires: Network for VPC/subnets, EKS for cluster name

4. DNS Stack (Route53 zones, certificates, ExternalDNS IRSA)
   make apply STACK=dns ENV=dev
   # Requires: EKS OIDC provider for IRSA
   # Auto-fetches: cloudflare_api_token via Infisical CLI (if installed)
```

**Note**: 
- Order is critical - EKS must create `infisical-credentials` before ArgoCD deploys ClusterSecretStore
- DNS stack auto-fetches Cloudflare token if Infisical CLI is installed, otherwise set `TF_VAR_cloudflare_api_token` in `.env`

### **Application Deployment (ArgoCD)**
```yaml
# ArgoCD Application manifest
spec:
  source:
  repoURL: http://gitlab-server.vpc.internal/user/repo.git
    path: k8s-manifests
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
```

---

## 🎯 **Key Design Decisions**

### **Why SSM-Only Access?**
- ✅ **No attack surface**: No public IPs for CICD
- ✅ **IAM integration**: Leverage existing AWS IAM
- ✅ **Audit trail**: CloudTrail logs all sessions
- ✅ **Cost savings**: No bastion hosts or VPN

### **Why Custom NAT Instance?**
- ✅ **Cost**: ~$7/month vs ~$45/month for NAT Gateway
- ✅ **Flexibility**: Can customize routing/filtering
- ✅ **SSM access**: Can troubleshoot NAT via SSM

### **Why Private DNS Zone?**
- ✅ **Clean URLs**: `gitlab-server.vpc.internal` vs `10.10.11.42`
- ✅ **Maintainable**: IP changes don't break configs
- ✅ **Standard**: Industry best practice for internal DNS

### **Why Localhost Communication?**
- ✅ **Container-friendly**: Services reference themselves as localhost
- ✅ **Port-forward compatible**: SSM port-forward works seamlessly
- ✅ **Cross-service via DNS**: Other services use private DNS FQDNs

---

## 🧪 **Testing & Verification**

### **Automated Verification**
```bash
# Run complete infrastructure verification
./scripts/verify-infrastructure.sh

# Checks performed:
# - VPC and networking
# - NAT instance status
# - CICD instances (GitLab, Jenkins)
# - EKS cluster health
# - DNS zones and records
# - Certificate validation
```

### **Manual Testing**
```bash
# Test private DNS resolution from EKS
kubectl run test --image=busybox --rm -it -- nslookup gitlab-server.vpc.internal

# Test SSM access to GitLab
aws ssm start-session --target $(terraform -chdir=envs/dev/cicd output -raw gitlab_server_id)
```

### **Certificate Validation**
```bash
# Check certificate status
CERT_ARN=$(terraform -chdir=envs/dev/dns output -raw app_certificate_arn)
aws acm describe-certificate --certificate-arn "$CERT_ARN" --query 'Certificate.Status'
# Should return: "ISSUED"
```

### **Application Access**
```bash
# After deploying app with Ingress
curl -I https://app.dev.r53.infinity.ortflix.uk
# Should return: 200 OK with valid TLS
```

---

## 📚 **Related Documentation**

- **[README.md](README.md)**: Quick start, deployment guide, scripts reference, practical operations
- **[K8S_INTEGRATION.md](K8S_INTEGRATION.md)**: Kubernetes manifests for ALB Controller, ExternalDNS, sample apps
- **[Makefile](Makefile)**: Terraform command shortcuts

---

## 🎉 **Summary**

This architecture provides:

- ✅ **Security**: SSM-only access, private subnets, no public IPs for CICD
- ✅ **Cost Optimization**: Custom NAT instance (~$7/mo vs ~$45/mo NAT Gateway)
- ✅ **Automation**: Auto-configured Jenkins agents, DNS validation, IRSA roles
- ✅ **Maintainability**: Private DNS for clean hostnames, modular stack design
- ✅ **Scalability**: EKS with managed nodes, ALB ingress, ExternalDNS

**For deployment instructions and operational guides, see [README.md](README.md)**
