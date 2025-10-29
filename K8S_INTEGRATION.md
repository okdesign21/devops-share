# 🔗 **Kubernetes Integration Guide**

## 🎯 **QUICK ANSWER: ArgoCD Repository URL**

**BEST OPTION: Use hostname resolution (NOW CONFIGURED!)**
```yaml
# In ArgoCD Application manifest:
spec:
  source:
    repoURL: http://gitlab-server.internal.local  # Clean hostname with private DNS
    path: k8s-manifests
    targetRevision: HEAD
```

**Why hostname is better than IP:**
- ✅ **Clean & maintainable** - no hardcoded IPs
- ✅ **Instance replacement friendly** - IP can change, hostname stays the same  
- ✅ **Private DNS configured** - Route53 private zone `internal.local` created
- ✅ **Standard practice** - industry standard for internal service discovery

**How DNS resolution works:**
1. **Private Route53 Zone**: `internal.local` zone attached to your VPC
2. **DNS A Records**: `gitlab-server.internal.local` → GitLab private IP
3. **VPC DNS**: EKS pods automatically use VPC DNS resolver
4. **Result**: `gitlab-server.internal.local` resolves from anywhere in VPC!

### **📋 Deployment Steps:**

```bash
# 1. Deploy network stack (creates VPC)
cd /home/or/devops-share/envs/dev/network
terraform apply

# 2. Deploy CICD stack (creates GitLab + Jenkins instances)  
cd /home/or/devops-share/envs/dev/cicd
terraform apply

# 3. Deploy DNS stack (creates private zone + A records)
cd /home/or/devops-share/envs/dev/dns
terraform apply

# 4. Verify hostname resolution works from EKS:
kubectl run test-pod --image=busybox --rm -it -- nslookup gitlab-server.internal.local
# Should return GitLab's private IP!

# 5. Use in ArgoCD Application:
# repoURL: http://gitlab-server.internal.local/your-username/your-repo.git
```

---

## 🚀 Deploy Infrastructure First

## Verify Certificate Status
```bash
# Get certificate ARN for Kubernetes integration
CERT_ARN=$(terraform -chdir=envs/dev/dns output -raw app_certificate_arn)
echo "Certificate ARN: $CERT_ARN"

# Check certificate validation status
aws acm describe-certificate --certificate-arn "$CERT_ARN" --query 'Certificate.Status' --output text
# Should show: ISSUED
```

---

## 📋 Kubernetes Manifests for ArgoCD

### 1. AWS Load Balancer Controller ServiceAccount

Create: `infrastructure/aws-load-balancer-controller/serviceaccount.yaml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT:role/irsa-alb-controller-dev
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
    app.kubernetes.io/managed-by: terraform
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: aws-load-balancer-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: aws-load-balancer-controller
    spec:
      serviceAccountName: aws-load-balancer-controller
      containers:
      - name: controller
        image: public.ecr.aws/eks/aws-load-balancer-controller:v2.7.2
        args:
        - --cluster-name=proj-dev-cluster
        - --ingress-class=alb
        - --region=us-east-1  # Replace with your region
        - --enable-waf=false
        - --enable-wafv2=false
        env:
        - name: AWS_DEFAULT_REGION
          value: us-east-1  # Replace with your region
        ports:
        - containerPort: 9443
          name: webhook-server
          protocol: TCP
        - containerPort: 8080
          name: metrics-server
          protocol: TCP
        volumeMounts:
        - mountPath: /tmp/k8s-webhook-server/serving-certs
          name: cert
          readOnly: true
        livenessProbe:
          httpGet:
            path: /healthz
            port: 61779
          initialDelaySeconds: 30
          timeoutSeconds: 10
        readinessProbe:
          httpGet:
            path: /readyz
            port: 61779
          initialDelaySeconds: 10
          timeoutSeconds: 10
      volumes:
      - name: cert
        secret:
          defaultMode: 420
          secretName: aws-load-balancer-webhook-tls
      terminationGracePeriodSeconds: 10
      nodeSelector:
        kubernetes.io/os: linux
```

### 2. ExternalDNS Configuration

Create: `infrastructure/external-dns/namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
  labels:
    name: external-dns
```

Create: `infrastructure/external-dns/serviceaccount.yaml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT:role/irsa-external-dns-dev
  labels:
    app.kubernetes.io/name: external-dns
    app.kubernetes.io/managed-by: terraform
```

Create: `infrastructure/external-dns/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
  labels:
    app.kubernetes.io/name: external-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: external-dns
  template:
    metadata:
      labels:
        app.kubernetes.io/name: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.14.0
        args:
        - --source=ingress
        - --source=service
        - --provider=aws
        - --aws-zone-type=public
        - --domain-filter=r53.YOUR_BASE_DOMAIN  # Replace with your domain
        - --policy=upsert-only
        - --registry=txt
        - --txt-owner-id=proj-dev-cluster
        - --txt-prefix=external-dns-
        - --interval=1m
        - --log-format=json
        - --log-level=info
        env:
        - name: AWS_DEFAULT_REGION
          value: us-east-1  # Replace with your region
        ports:
        - containerPort: 7979
          name: http
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 2
        readinessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
      securityContext:
        fsGroup: 65534
```

### 3. Sample App with TLS Ingress

Create: `applications/sample-app/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app
  namespace: default
spec:
  type: ClusterIP  # Important: ClusterIP, not LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: sample-app
```

Create: `applications/sample-app/ingress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app-ingress
  namespace: default
  annotations:
    # ALB Configuration
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    
    # TLS Configuration (REPLACE WITH YOUR CERTIFICATE ARN)
    alb.ingress.kubernetes.io/certificate-arn: "REPLACE_WITH_CERTIFICATE_ARN_FROM_TERRAFORM"
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    
    # ExternalDNS Configuration (REPLACE WITH YOUR DOMAIN)
    external-dns.alpha.kubernetes.io/hostname: "app.dev.r53.YOUR_BASE_DOMAIN"
    
    # Optional: Additional ALB settings
    alb.ingress.kubernetes.io/group.name: public-alb
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
    alb.ingress.kubernetes.io/success-codes: '200'
    
  labels:
    app: sample-app
spec:
  rules:
  - host: app.dev.r53.YOUR_BASE_DOMAIN  # Replace with your domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app
            port:
              number: 80
  # TLS section (ALB handles termination, this is for documentation)
  tls:
  - hosts:
    - app.dev.r53.YOUR_BASE_DOMAIN
```

### 4. Weather App Example (Uses SAN on Certificate)

Create: `applications/weather-app/ingress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: weather-app-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    
    # Same certificate ARN (SAN covers weather.dev.r53.domain)
    alb.ingress.kubernetes.io/certificate-arn: "REPLACE_WITH_CERTIFICATE_ARN_FROM_TERRAFORM"
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    
    # Weather-specific domain
    external-dns.alpha.kubernetes.io/hostname: "weather.dev.r53.YOUR_BASE_DOMAIN"
    
    # Share the same ALB
    alb.ingress.kubernetes.io/group.name: public-alb
    
spec:
  rules:
  - host: weather.dev.r53.YOUR_BASE_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: weather-app-service
            port:
              number: 80
```

---

## 🔧 Deployment Steps

### 1. Get Certificate ARN from Terraform
```bash
cd /home/or/devops-share

# Deploy DNS stack with certificate
make apply STACK=dns ENV=dev

# Get certificate ARN
CERT_ARN=$(terraform -chdir=envs/dev/dns output -raw app_certificate_arn)
echo "Certificate ARN: $CERT_ARN"

# Get your domain from Terraform
APP_DOMAIN=$(terraform -chdir=envs/dev/dns output -raw app_domain_name)
echo "App Domain: $APP_DOMAIN"
```

### 2. Replace Placeholders in Kubernetes Manifests
```bash
# Replace certificate ARN in all ingress files
sed -i "s|REPLACE_WITH_CERTIFICATE_ARN_FROM_TERRAFORM|$CERT_ARN|g" applications/*/ingress.yaml

# Replace domain names (adjust YOUR_BASE_DOMAIN to your actual domain)
sed -i "s|YOUR_BASE_DOMAIN|your-actual-domain.com|g" infrastructure/external-dns/deployment.yaml
sed -i "s|YOUR_BASE_DOMAIN|your-actual-domain.com|g" applications/*/ingress.yaml

# Replace AWS account ID in IRSA annotations
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s|YOUR_ACCOUNT|$ACCOUNT_ID|g" infrastructure/*/serviceaccount.yaml
```

### 3. Deploy to Kubernetes (ArgoCD Applications)
```bash
# Apply infrastructure first
kubectl apply -f infrastructure/

# Wait for controllers to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-dns -n external-dns --timeout=300s

# Deploy applications
kubectl apply -f applications/
```

### 4. Verify Deployment
```bash
# Check ALB creation
kubectl get ingress -A
kubectl describe ingress sample-app-ingress

# Check DNS record creation (may take 1-2 minutes)
nslookup app.dev.r53.your-domain.com

# Test HTTPS access
curl -I https://app.dev.r53.your-domain.com
```

---

## 🛠️ Troubleshooting

### Certificate Issues
```bash
# Check certificate status
aws acm describe-certificate --certificate-arn "$CERT_ARN"

# Check Route53 validation records
aws route53 list-resource-record-sets --hosted-zone-id $(terraform -chdir=envs/dev/dns output -raw r53_zone_id)
```

### ALB Controller Issues
```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check IRSA role
kubectl describe serviceaccount aws-load-balancer-controller -n kube-system
```

### ExternalDNS Issues
```bash
# Check ExternalDNS logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Check permissions
kubectl describe serviceaccount external-dns -n external-dns
```

---

## 📝 Summary

1. **Terraform manages:** ACM certificate + DNS validation
2. **Kubernetes uses:** Certificate ARN in Ingress annotations
3. **ALB Controller:** Creates ALB with TLS termination
4. **ExternalDNS:** Creates Route53 records pointing to ALB
5. **Result:** Fully automated HTTPS app deployment!

**Certificate covers:**
- `dev.r53.your-domain.com` (primary)
- `*.dev.r53.your-domain.com` (wildcard SAN)
- `weather.dev.r53.your-domain.com` (additional SAN)