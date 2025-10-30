# 🔐 Infrastructure Access Guide

**Generated on:** Thu Oct 30 12:54:04 PM IST 2025  
**Environment:** dev  
**Region:** eu-central-1

---

## 📋 Quick Reference

| Service | Instance ID | Private IP | Access Method |
|---------|------------|------------|---------------|
| GitLab | `i-0b2bb85141818b24e` | 10.10.12.43 | SSM Session / Port-Forward |
| Jenkins | `i-09bb68a84681c6b13` | 10.10.11.72 | SSM Session / Port-Forward |
| NAT Instance | `i-0fab6084cbab812f7` | 18.194.41.61 (public) | SSM Session |
| EKS Cluster | `proj-dev-cluster` | N/A | kubectl |

---

## 🔌 SSM Session (Shell Access)

### GitLab Server
```bash
aws ssm start-session --target i-0b2bb85141818b24e
```

**Once connected, useful commands:**
```bash
# Check GitLab container status
docker ps

# View GitLab logs
docker logs gitlab

# Check GitLab service
docker exec gitlab gitlab-ctl status
```

---

### Jenkins Server
```bash
aws ssm start-session --target i-09bb68a84681c6b13
```

**Once connected, useful commands:**
```bash
# Check Jenkins container status
docker ps

# View Jenkins logs
docker logs jenkins

# Get initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

### NAT Instance
```bash
aws ssm start-session --target i-0fab6084cbab812f7
```

**Once connected, useful commands:**
```bash
# Check NAT forwarding
sudo sysctl net.ipv4.ip_forward

# View iptables NAT rules
sudo iptables -t nat -L -n -v

# Monitor network traffic
sudo tcpdump -i any -n
```

---

## 🌐 SSM Port Forwarding (Web Access)

### GitLab Web UI
**Access GitLab at:** `http://localhost:8443`

```bash
aws ssm start-session \
  --target i-0b2bb85141818b24e \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8443"]}'
```

**Default credentials:**
- Username: `root`
- Password: Check with `docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password` (via SSM session)

---

### Jenkins Web UI
**Access Jenkins at:** `http://localhost:8080`

```bash
aws ssm start-session \
  --target i-09bb68a84681c6b13 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

**Initial admin password:**
```bash
# Run this via SSM session first:
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## ☸️ Kubernetes (EKS) Access

### Update kubeconfig
```bash
aws eks update-kubeconfig \
  --name proj-dev-cluster \
  --region eu-central-1
```

### Verify cluster access
```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

### Test private DNS from inside cluster
```bash
# Test GitLab DNS resolution
kubectl run dns-test --image=busybox:1.28 --rm -it --restart=Never -- nslookup gitlab-server.internal.local

# Test Jenkins DNS resolution
kubectl run dns-test --image=busybox:1.28 --rm -it --restart=Never -- nslookup jenkins-server.internal.local
```

---

## 🔧 Kubernetes Controllers Setup

### 1. AWS Load Balancer Controller

**Install with Helm:**
```bash
# Add EKS chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=proj-dev-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::318865045755:role/irsa-alb-controller-dev"
```

**Verify:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

---

### 2. ExternalDNS

**Create namespace:**
```bash
kubectl create namespace external-dns
```

**Install with Helm:**
```bash
# Add bitnami chart repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install ExternalDNS
helm install external-dns bitnami/external-dns \
  -n external-dns \
  --set provider=aws \
  --set aws.region=eu-central-1 \
  --set domainFilters[0]=r53.infinity.ortflix.uk \
  --set policy=sync \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-dns \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::318865045755:role/irsa-external-dns-dev"
```

**Verify:**
```bash
kubectl get deployment -n external-dns
kubectl logs -n external-dns deployment/external-dns
```

---

## 🚀 Deploy Sample Application

### Simple Test App with Ingress

**Create deployment:**
```bash
cat <<'EOFAPP' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: hello
        image: hashicorp/http-echo
        args:
          - "-text=Hello from EKS!"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: hello-service
spec:
  type: ClusterIP
  selector:
    app: hello
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-central-1:318865045755:certificate/ad8df8e3-1bae-4407-a94c-f45909d9f64e
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    external-dns.alpha.kubernetes.io/hostname: app.dev.r53.infinity.ortflix.uk
spec:
  ingressClassName: alb
  rules:
  - host: app.dev.r53.infinity.ortflix.uk
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-service
            port:
              number: 80
EOFAPP
```

**Check deployment:**
```bash
# Wait for ALB to be created (2-3 minutes)
kubectl get ingress hello-ingress -w

# Get ALB DNS name
kubectl get ingress hello-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test the app (after DNS propagates)
curl https://app.dev.r53.infinity.ortflix.uk
```

---

## 🧪 Troubleshooting Commands

### Check SSM connectivity
```bash
# List all SSM-managed instances
aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]' \
  --output table

# Check specific instance
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-0b2bb85141818b24e" \
  --query 'InstanceInformationList[0].PingStatus'
```

### Check Route53 records
```bash
# List public zone records
aws route53 list-resource-record-sets \
  --hosted-zone-id $(aws route53 list-hosted-zones --query "HostedZones[?Name=='r53.infinity.ortflix.uk.'].Id" --output text | cut -d'/' -f3)

# List private zone records
aws route53 list-resource-record-sets \
  --hosted-zone-id $(aws route53 list-hosted-zones --query "HostedZones[?Name=='internal.local.'].Id" --output text | cut -d'/' -f3)
```

### Check EKS node health
```bash
kubectl get nodes -o wide
kubectl describe nodes
kubectl top nodes  # Requires metrics-server
```

### Check ALB Controller logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100 -f
```

### Check ExternalDNS logs
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=100 -f
```

---

## 📊 Infrastructure Details

### Network
- **VPC ID:** `vpc-01eb2563ece5706bb`
- **NAT Instance Public IP:** `18.194.41.61`
- **Region:** `eu-central-1`

### CICD Services
- **GitLab Private IP:** `10.10.12.43`
- **Jenkins Private IP:** `10.10.11.72`
- **Private DNS Zone:** `internal.local`

### DNS
- **Public Zone:** `r53.infinity.ortflix.uk`
- **App Domain:** `app.dev.r53.infinity.ortflix.uk`
- **Wildcard:** `*.dev.r53.infinity.ortflix.uk`

### IAM Roles (IRSA)
- **ExternalDNS Role:** `arn:aws:iam::318865045755:role/irsa-external-dns-dev`
- **ALB Controller Role:** `arn:aws:iam::318865045755:role/irsa-alb-controller-dev`

---

## 🔄 Regenerate This File

To update this file with latest infrastructure values:
```bash
./generate-access-commands.sh
```

---

**Need help?** Check `ARCHITECTURE.md` for architecture details or run `./verify-infrastructure.sh` to test connectivity.
