# 🔗 **Kubernetes Integration Guide**

## 🎯 **ArgoCD Repository URL**

Use internal DNS for GitLab repository access:

```yaml
# In ArgoCD Application manifest:
spec:
  source:
    repoURL: http://gitlab-server.internal.local/your-username/your-repo.git
    path: k8s-manifests
    targetRevision: HEAD
```

**How it works:**
- Private Route53 zone `internal.local` is attached to your VPC
- DNS A record: `gitlab-server.internal.local` → GitLab private IP
- EKS pods automatically use VPC DNS resolver
- GitLab is accessible from anywhere in the VPC!

---

## 📋 Getting Started

### 1. Generate Access Documentation
```bash
# Generate complete access guide with all IDs and commands
make access-guide

# View the guide
cat INFRASTRUCTURE_ACCESS.md
```

The generated guide includes:
- Pre-filled instance IDs
- Certificate ARNs
- Helm installation commands
- Sample application deployments
- All necessary kubectl commands

### 2. Update Kubeconfig
```bash
# Get the command from Terraform
terraform -chdir=envs/dev/eks output -raw kubeconfig_command

# Or directly
aws eks update-kubeconfig --name proj-dev-cluster --region eu-central-1
```

### 3. Install Controllers

Follow the commands in `INFRASTRUCTURE_ACCESS.md` to install:
- **AWS Load Balancer Controller** (with pre-filled cluster name and role ARN)
- **ExternalDNS** (with pre-filled domain and role ARN)

---

## 🚀 Deploy Sample Application

The `INFRASTRUCTURE_ACCESS.md` guide includes a ready-to-deploy sample application with:
- Deployment (2 replicas)
- ClusterIP Service
- Ingress with ALB annotations
- Pre-configured certificate ARN
- ExternalDNS hostname

Just copy-paste the command from the generated guide!

---

## 🧪 Testing

```bash
# Check if controllers are running
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get deployment -n external-dns

# Deploy the sample app (from INFRASTRUCTURE_ACCESS.md)
# Wait for ALB creation (2-3 minutes)
kubectl get ingress -w

# Test access
curl https://app.dev.r53.infinity.ortflix.uk
```

---

## 📚 Reference

For manual Kubernetes manifest creation, here are the key patterns:

### Ingress Annotations
```yaml
annotations:
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/certificate-arn: <from-terraform-output>
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
  alb.ingress.kubernetes.io/ssl-redirect: '443'
  external-dns.alpha.kubernetes.io/hostname: app.dev.r53.infinity.ortflix.uk
```

### Service Type
```yaml
spec:
  type: ClusterIP  # Important: NOT LoadBalancer
```

**For complete examples, see `INFRASTRUCTURE_ACCESS.md` which is auto-generated with your actual infrastructure values!**
