# 🔐 SSM Access Guide

## Overview

Access CICD services (GitLab, Jenkins) via AWS Systems Manager port forwarding - no public IPs, no bastion hosts, no SSH keys required.

---

## 🚀 **Quick Access Commands**

### **GitLab** (access on localhost:8443)
```bash
# Get GitLab instance ID
GITLAB_ID=$(terraform -chdir=envs/dev/cicd output -raw gitlab_server_id)

# Start port forwarding
aws ssm start-session --target $GITLAB_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8443"]}'

# Access in browser
open http://localhost:8443
```

### **Jenkins** (access on localhost:8080)
```bash
# Get Jenkins instance ID
JENKINS_ID=$(terraform -chdir=envs/dev/cicd output -raw jenkins_server_id)

# Start port forwarding
aws ssm start-session --target $JENKINS_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'

# Access in browser
open http://localhost:8080
```

---

## 🔧 **How It Works**

### **Architecture**
```
Developer (IAM) → SSM Service → Private Instance
```

**Benefits:**
- ✅ No public IPs or load balancers
- ✅ IAM-based access control
- ✅ CloudTrail audit logs
- ✅ No SSH keys or VPN

### **Access Flow**
1. Developer runs `aws ssm start-session`
2. SSM validates IAM permissions
3. Session established to private instance
4. Local port forwards to instance port
5. Access service on `localhost`

---

## 👥 **IAM Permissions**

### **Automatic Setup**
Terraform automatically creates and attaches SSM access policy to "Devs" IAM group.

### **Required Policy** (auto-created)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ssm:StartSession"],
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringEquals": {
          "ssm:resourceTag/Project": "proj",
          "ssm:resourceTag/Environment": "dev"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:StartSession"],
      "Resource": "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSession"
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:TerminateSession", "ssm:ResumeSession"],
      "Resource": "arn:aws:ssm:*:*:session/${aws:userid}-*"
    }
  ]
}
```

### **Add User to Devs Group**
```bash
# Add existing IAM user to Devs group
aws iam add-user-to-group --user-name <username> --group-name Devs

# Verify membership
aws iam get-group --group-name Devs
```

---

## 🧪 **Testing Access**

### **1. Verify Instance is SSM-Ready**
```bash
# List SSM-managed instances
aws ssm describe-instance-information \
  --filters "Key=tag:Project,Values=proj" \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]' \
  --output table
```

### **2. Test Basic SSM Session**
```bash
# Interactive shell session
aws ssm start-session --target <instance-id>

# Inside session, verify services:
docker ps
```

### **3. Test Port Forwarding**
```bash
# GitLab port forward
aws ssm start-session --target $GITLAB_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8443"]}'

# In another terminal:
curl -I http://localhost:8443
# Should return HTTP 200/302
```

---

## 🔍 **Troubleshooting**

### **"Session cannot be started" Error**

**Check instance has SSM agent:**
```bash
aws ssm describe-instance-information \
  --instance-information-filter-list key=InstanceIds,valueSet=<instance-id>
```

**Verify IAM instance profile:**
```bash
aws ec2 describe-instances --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
# Should show: .../proj-dev-ssm-instance-profile
```

### **Permission Denied**

**Check your IAM group membership:**
```bash
aws iam get-groups-for-user --user-name $(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)
# Should include "Devs" group
```

**Verify policy attached to Devs group:**
```bash
aws iam list-attached-group-policies --group-name Devs
```

### **Port Already in Use**

**Kill existing session:**
```bash
# List running SSM sessions
aws ssm describe-sessions --state Active

# Terminate session
aws ssm terminate-session --session-id <session-id>

# Or kill local port forwarding process
lsof -ti:8443 | xargs kill -9
```

---

## 💡 **Best Practices**

1. **Use Instance IDs from Terraform Outputs**
   ```bash
   # Store in environment variables
   export GITLAB_ID=$(terraform -chdir=envs/dev/cicd output -raw gitlab_server_id)
   export JENKINS_ID=$(terraform -chdir=envs/dev/cicd output -raw jenkins_server_id)
   ```

2. **Create Shell Aliases**
   ```bash
   # Add to ~/.zshrc or ~/.bashrc
   alias gitlab-ssm='aws ssm start-session --target $GITLAB_ID ...'
   alias jenkins-ssm='aws ssm start-session --target $JENKINS_ID ...'
   ```

3. **Use Session Manager Plugin**
   ```bash
   # Install if not present
   brew install --cask session-manager-plugin  # macOS
   ```

4. **Monitor Active Sessions**
   ```bash
   # List your active sessions
   aws ssm describe-sessions --state Active \
     --filters "key=Owner,value=$(aws sts get-caller-identity --query 'Arn' --output text)"
   ```

---

## 📊 **Port Mapping Reference**

| Service | Instance Port | Local Port | URL |
|---------|--------------|------------|-----|
| GitLab  | 80           | 8443       | http://localhost:8443 |
| Jenkins | 8080         | 8080       | http://localhost:8080 |

---

## 🔗 **Related Documentation**

- [README.md](README.md) - Quick start and deployment
- [ARCHITECTURE.md](ARCHITECTURE.md) - Full architecture overview

---

**Access is IAM-based and secure - no public exposure!** 🔒
