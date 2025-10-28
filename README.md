# Dev Environment Terraform Guide

This repository contains Terraform stacks that stand up the "dev" environment for the project. The stacks break down into four logical layers:

- `network` – VPC, subnets, NAT instance, IAM and SSH bootstrap.
- `cicd` – EC2-based CI/CD services and supporting networking.
- `eks` – EKS control plane, managed node groups, and cluster add-ons.
- `dns` – Route53 private zone and Cloudflare public records linked to the other stacks.

All stacks share remote state stored in **S3 bucket** `tfstate-inf-orinbar-euc1` under the prefix `cicd/<env>/<stack>/terraform.tfstate`.

---

## Prerequisites

- Terraform ≥ 1.5
- AWS CLI v2 with credentials that can manage the target account (region `eu-central-1`).
- Access to the S3 backend bucket `tfstate-inf-orinbar-euc1`.
- Optional: `make` for the wrapper commands.

Ensure the AWS CLI profile you plan to use is already authenticated:

```bash
aws sts get-caller-identity
```

---

## Quick Start (dev environment)

1. **Clone repo & move into it.**

2. **Configure backend:** the Makefile drives the backend key using `STATE_PREFIX` (defaults to `cicd`). To initialise all stacks:

```bash
make init ENV=dev STATE_PREFIX=cicd
```

3. **Plan or apply individual stacks** to keep your workstation load light. Recommended sequence:

```bash
make plan  ENV=dev STACK=network
make apply ENV=dev STACK=network

make plan  ENV=dev STACK=cicd
make apply ENV=dev STACK=cicd

# EKS is staged across two stacks—see note below
make plan  ENV=dev STACK=eks
make apply ENV=dev STACK=eks

make plan  ENV=dev STACK=eks-addons
make apply ENV=dev STACK=eks-addons

make plan  ENV=dev STACK=dns
make apply ENV=dev STACK=dns
```

You can still run everything at once (`STACK=all`), but staggered applies are friendlier to local resources.

4. **Destroy when finished:**

```bash
make destroy ENV=dev STATE_PREFIX=cicd
```

Stacks destroy in reverse order (dns → eks → cicd → network).

---

## EKS Two-Phase Apply

The EKS rollout is intentionally split into two stacks:

1. **Cluster (stack `eks`)** – creates the control plane, managed node groups, and IAM plumbing (including the AWS Load Balancer Controller role).
  ```bash
  # run with defaults to build the cluster
  make apply ENV=dev STACK=eks
  ```

2. **Add-ons (stack `eks-addons`)** – installs the AWS Load Balancer Controller, Argo CD, and supporting Kubernetes objects.
  - Flip `deploy_addons` to `true` in `envs/dev/eks-addons/terraform.tfvars` (or pass `-var deploy_addons=true`).
  ```bash
  make apply ENV=dev STACK=eks-addons
  ```

Run the second step only after the cluster reports `ACTIVE`. Keeping Helm/Kubernetes resources in their own stack avoids provider connection errors while the control plane is still coming online.

---

## Destroying the Environment

### Prerequisites

**Before running Terraform destroy**, clean up Kubernetes resources that create AWS dependencies:

1. Clone the ArgoCD repository
2. Run the pre-destroy script:
   ```bash
   cd /path/to/argocd-repo
   ./scripts/pre-destroy.sh proj-dev-cluster eu-central-1 argocd
   ```
3. Wait for completion (~5 minutes)

### Destroy Sequence

```bash
# After running pre-destroy.sh:
make destroy ENV=dev STACK=dns      # Now safe - Route53 records cleaned
make destroy ENV=dev STACK=eks      # EKS cluster + node groups
make destroy ENV=dev STACK=cicd     # Jenkins/GitLab instances
make destroy ENV=dev STACK=network  # VPC and NAT instance
```

### Emergency Manual Cleanup

If destroy still fails:

1. **Check for orphaned LoadBalancers:**
   ```bash
   aws elbv2 describe-load-balancers --query 'LoadBalancers[?VpcId==`vpc-xxxxx`]'
   ```

2. **Force delete Route53 records:**
   ```bash
   python3 scripts/delete-route53-records.py dev.r53.infinity.ortflix.uk
   ```

3. **Remove dangling ENIs:**
   ```bash
   aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=vpc-xxxxx \
     --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' | \
     xargs -n1 aws ec2 delete-network-interface --network-interface-id
   ```

---

## Handling Existing Resources

If an AWS resource already exists (for example `proj-key` or `proj-ssm-ec2-role`), import it instead of deleting it:

```bash
cd envs/dev/network
terraform init -reconfigure \
  -backend-config=../../backend.hcl \
  -backend-config="key=cicd/dev/network/terraform.tfstate"

terraform import -var-file=../../common.tfvars 'aws_key_pair.gen[0]' proj-key
terraform import -var-file=../../common.tfvars aws_iam_role.ssm_ec2 proj-ssm-ec2-role
```

After importing, run `terraform plan` to confirm a clean state. Adjust resource definitions (for example, supplying a `public_key`) if Terraform still wants to recreate them.

---

## Variables & tfvars

- `envs/common.tfvars` supplies shared values (`state_bucket`, `state_prefix`, CIDR blocks, etc.).
- Each stack reads the same file; unused values trigger warnings that can be safely ignored for now.
- Sensitive values (tokens, passwords) should be provided through environment variables or a secret store in future iterations.

---

## Operational Tips

- Always run `make init` after modifying backend settings or cloning the repo onto a new machine.
- Use `make plan` routinely to catch drift before applying changes.
- Keep local copies of the remote state (see `state-backups/`) before destructive work.
- When troubleshooting EKS applies, AWS CLI helpers such as `aws eks describe-nodegroup` and `aws ec2 describe-instances` are invaluable for surfacing node health issues.

---

## Next Improvements

- Migrate sensitive tokens to AWS Secrets Manager or SSM Parameter Store.
- Add stack-specific variable files to silence Terraform variable warnings.
- Automate common imports (key pairs, IAM roles) via scripts if drift recurs.

This README keeps the essentials front and centre so you can bootstrap, iterate, and tear down the dev environment quickly. Reach out to update it whenever the provisioning flow changes.

## Stack Dependencies
  network --> cicd
  network --> eks
  cicd --> dns
  eks --> dns