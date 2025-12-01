# Adding a New Environment

## Quick Guide: Adding a New Environment (e.g., `staging`)

### **1. Create Environment Directory Structure**
```bash
# From project root
mkdir -p envs/staging/{network,cicd,dns,eks}
```

### **2. Create Symlinks to Shared Configs**
```bash
# Network
cd envs/staging/network
ln -s ../../_shared/network/main.tf .
ln -s ../../_shared/network/variables.tf .
ln -s ../../_shared/network/outputs.tf .
ln -s ../../_shared/network/providers.tf .
ln -s ../../_shared/network/keygen.tf .

# CICD
cd ../cicd
ln -s ../../_shared/cicd/main.tf .
ln -s ../../_shared/cicd/variables.tf .
ln -s ../../_shared/cicd/outputs.tf .
ln -s ../../_shared/cicd/providers.tf .

# DNS
cd ../dns
ln -s ../../_shared/dns/main.tf .
ln -s ../../_shared/dns/variables.tf .
ln -s ../../_shared/dns/outputs.tf .
ln -s ../../_shared/dns/providers.tf .

# EKS
cd ../eks
ln -s ../../_shared/eks/main.tf .
ln -s ../../_shared/eks/variables.tf .
ln -s ../../_shared/eks/outputs.tf .
ln -s ../../_shared/eks/providers.tf .
```

**OR use a helper script:**
```bash
#!/bin/bash
NEW_ENV=$1
for stack in network cicd dns eks; do
  mkdir -p envs/$NEW_ENV/$stack
  cd envs/$NEW_ENV/$stack
  for tf in ../../_shared/$stack/*.tf; do
    ln -s $tf .
  done
  cd ../../..
done
```

### **3. Create Environment-Specific Variable Files**
```bash
# Common variables for staging
cat > envs/staging/staging-common.tfvars <<EOF
project_name = "proj"
env          = "staging"
region       = "eu-central-1"
EOF

# Network-specific
cat > envs/staging/network/network.auto.tfvars <<EOF
vpc_cidr = "15.10.0.0/16"  # Different CIDR than dev/prod
# ... other network-specific values
EOF

# Copy and adjust other .auto.tfvars from dev
cp envs/dev/cicd/cicd.auto.tfvars envs/staging/cicd/
cp envs/dev/dns/dns.auto.tfvars envs/staging/dns/
cp envs/dev/eks/eks.auto.tfvars envs/staging/eks/

# Edit each file to adjust staging-specific values
```

### **4. Update Backend Configuration (if needed)**
If staging needs a different S3 bucket or path:
```bash
# Either use the same backend.hcl with different key prefix (recommended)
# Or create envs/staging/backend.hcl with custom settings
```

### **5. Update Makefile**
```makefile
# Add staging to environment list
STAGING_STACKS := network cicd eks dns
STACKS := $(if $(filter prod,$(ENV)),$(PROD_STACKS),\
          $(if $(filter staging,$(ENV)),$(STAGING_STACKS),\
          $(DEV_STACKS)))
```

### **6. Deploy**
```bash
make init ENV=staging
make apply STACK=network ENV=staging
make apply STACK=cicd ENV=staging
make apply STACK=eks ENV=staging
make apply STACK=dns ENV=staging
```

---

## **Summary: Steps to Add New Environment**
1. ✅ Create directory: `envs/<new-env>/{network,cicd,dns,eks}`
2. ✅ Symlink `.tf` files from `_shared/`
3. ✅ Create `<env>-common.tfvars` and `*.auto.tfvars` files
4. ✅ Update Makefile (add env to STACKS logic)
5. ✅ Run `make init ENV=<new-env>` then deploy

**Zero code duplication required!** 🎉
