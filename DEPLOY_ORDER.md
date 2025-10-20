# Deployment Order

1. **network** - VPC, subnets, IGW, NAT
2. **cicd** - GitLab Runner / Jenkins agents
3. **eks** - EKS cluster, ArgoCD, ALB controller
4. **dns** - Cloudflare & Route53 DNS records

## Commands
```bash
# Deploy all (in order)
make apply STACK=all ENV=dev

# Deploy single stack
make apply STACK=eks ENV=dev

# Destroy all (reverse order)
make destroy STACK=all ENV=dev
```