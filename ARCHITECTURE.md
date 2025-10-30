# 🏗️ Infrastructure Architecture

## 📋 **Overview**

Multi-stack AWS infrastructure with Terraform for development and production environments:
- **Network**: VPC, subnets, NAT instance, SSM access
- **CICD**: GitLab & Jenkins (SSM-only, private DNS)
- **DNS**: Route53 public zone + private zone for internal service discovery
- **EKS**: Kubernetes cluster with ALB controller & ExternalDNS

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
- **GitLab**: Version control, CI/CD pipelines
- **Jenkins**: Build automation, deployment orchestration
- **Jenkins Agents**: Ephemeral build executors

### **Access Pattern**
```bash
# Developer → SSM Port-Forward → GitLab (localhost:8443)
aws ssm start-session --target i-gitlab123 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8443"]}'

# Developer → SSM Port-Forward → Jenkins (localhost:8080)  
aws ssm start-session --target i-jenkins456 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

### **Internal Communication**
- **GitLab self-reference**: `http://localhost` (container → localhost)
- **Jenkins self-reference**: `http://localhost:8080` (container → localhost)
- **Jenkins → GitLab**: `http://gitlab-server.internal.local` (via private DNS)
- **Jenkins ← Agents**: `http://jenkins-server.internal.local:8080` (via private DNS)

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
Zone: internal.local (VPC-scoped)

Records:
  gitlab-server.internal.local  → 10.10.11.X
  jenkins-server.internal.local → 10.10.11.Y
```

**Purpose**: Clean hostname resolution for internal services (GitLab, Jenkins, ArgoCD)

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
```bash
1. Network Stack (VPC, subnets, NAT, SSM)
   cd envs/dev/network && terraform apply

2. CICD Stack (GitLab, Jenkins instances)
   cd envs/dev/cicd && terraform apply

3. EKS Stack (cluster, nodes, IRSA roles)
   cd envs/dev/eks && terraform apply

4. DNS Stack (Route53 zones, certificates, private DNS, ExternalDNS IRSA)
   cd envs/dev/dns && terraform apply
   # Requires: EKS OIDC provider for ExternalDNS IRSA trust policy
```

### **Application Deployment (ArgoCD)**
```yaml
# ArgoCD Application manifest
spec:
  source:
    repoURL: http://gitlab-server.internal.local/user/repo.git
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
- ✅ **Clean URLs**: `gitlab-server.internal.local` vs `10.10.11.42`
- ✅ **Maintainable**: IP changes don't break configs
- ✅ **Standard**: Industry best practice for internal DNS

### **Why Localhost Communication?**
- ✅ **Container-friendly**: Services reference themselves as localhost
- ✅ **Port-forward compatible**: SSM port-forward works seamlessly
- ✅ **Cross-service via DNS**: Other services use private DNS FQDNs

---

## 🧪 **Testing & Verification**

### **Network Connectivity**
```bash
# Test private DNS resolution from EKS
kubectl run test --image=busybox --rm -it -- nslookup gitlab-server.internal.local

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

- **K8S_INTEGRATION.md**: Kubernetes manifests for ALB Controller, ExternalDNS, sample apps
- **README.md**: Quick start guide and deployment instructions
- **Makefile**: Common terraform commands for each stack

---

## 🎉 **Production Readiness**

**Status: READY FOR DEPLOYMENT** ✅

- ✅ Clean, organized multi-stack architecture
- ✅ Secure SSM-only access pattern
- ✅ Private DNS for internal service discovery
- ✅ Automated certificate management
- ✅ Kubernetes controllers with IRSA
- ✅ Cost-optimized NAT instance
- ✅ Environment isolation (dev/prod)

**Prod environment**: Copy dev configuration and adjust CIDRs/sizing as needed.
