#!/bin/bash
set -euo pipefail

cat > /opt/jenkins/.env <<'EOF'
JENKINS_PUBLIC_HOSTNAME=${public_hostname}
JENKINS_URL=${jenkins_url}
GITLAB_URL=${gitlab_url}
AGENT_HOSTNAME_OVERRIDE=${agent_override}
EOF

chown root:root /opt/jenkins/.env || true
chmod 640 /opt/jenkins/.env || true

# Configure kubeconfig for jenkins user to access EKS (if EKS exists)
if [ -n "${eks_cluster_name}" ]; then
  echo "Configuring EKS kubeconfig for cluster: ${eks_cluster_name}"
  mkdir -p /home/ubuntu/.kube
  if aws eks update-kubeconfig --region ${aws_region} --name ${eks_cluster_name} --kubeconfig /home/ubuntu/.kube/config 2>/dev/null; then
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
    chmod 600 /home/ubuntu/.kube/config
    echo "EKS kubeconfig configured successfully"
  else
    echo "WARNING: Failed to configure EKS kubeconfig (cluster may not be ready or no permissions)"
  fi
else
  echo "Skipping EKS kubeconfig setup (no EKS cluster configured)"
fi

# Create Jenkins Configuration as Code directory and config
mkdir -p /opt/jenkins/config/casc
mkdir -p /opt/jenkins/config/init.groovy.d

# Create JCasC configuration file
if [ -n "${eks_cluster_name}" ]; then
  # EKS exists - include Kubernetes cloud configuration
  cat > /opt/jenkins/config/casc/jenkins.yaml <<'CASC'
jenkins:
  systemMessage: "Jenkins configured automatically via JCasC"
  numExecutors: 0
  mode: EXCLUSIVE
  securityRealm:
    local:
      allowsSignup: false
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: true
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: true
  
unclassified:
  location:
    url: "${jenkins_url}"
    adminAddress: "admin@jenkins.local"
  kubernetesCloud:
    - name: "kubernetes"
      serverUrl: "https://kubernetes.default"
      skipTlsVerify: true
      namespace: "jenkins-agents"
      jenkinsUrl: "${jenkins_url}"
      jenkinsTunnel: "${public_hostname}:50000"
      credentialsId: ""
      webSocket: false
      directConnection: false
      containerCapStr: "100"
      maxRequestsPerHostStr: "32"
      retentionTimeout: 5
      connectTimeout: 0
      readTimeout: 0
      podLabels:
        - key: "jenkins"
          value: "agent"
      templates: []

# Kubernetes agents configured via plugin, no static nodes needed
      
security:
  remotingCLI:
    enabled: false
  gitLabConnectionConfig:
    useAuthenticatedEndpoint: false
  gitHubConfiguration:
    apiRateLimitChecker: ThrottleOnOver
  globalJobDslSecurityConfiguration:
    useScriptSecurity: true
CASC
else
  # No EKS - skip Kubernetes cloud configuration
  cat > /opt/jenkins/config/casc/jenkins.yaml <<'CASC'
jenkins:
  systemMessage: "Jenkins configured automatically via JCasC"
  numExecutors: 0
  mode: EXCLUSIVE
  securityRealm:
    local:
      allowsSignup: false
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: true
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: true
  
unclassified:
  location:
    url: "${jenkins_url}"
    adminAddress: "admin@jenkins.local"

# No Kubernetes agents - EKS not configured
      
security:
  remotingCLI:
    enabled: false
  gitLabConnectionConfig:
    useAuthenticatedEndpoint: false
  gitHubConfiguration:
    apiRateLimitChecker: ThrottleOnOver
  globalJobDslSecurityConfiguration:
    useScriptSecurity: true
CASC
fi

# Create quick startup script (Kubernetes agents don't need static agent secrets)
cat > /opt/jenkins/config/init.groovy.d/startup-complete.groovy <<'GROOVY'
import jenkins.model.Jenkins

println "✓ Jenkins startup complete - using Kubernetes dynamic agents"
println "✓ Kubernetes plugin will provision agents on-demand"
GROOVY

# Create init.groovy.d script to set Jenkins URL (backup method)
cat > /opt/jenkins/config/init.groovy.d/set-jenkins-url.groovy <<'GROOVY'
import jenkins.model.JenkinsLocationConfiguration

def jenkinsUrl = System.getenv('JENKINS_URL')
if (jenkinsUrl) {
    def config = JenkinsLocationConfiguration.get()
    config.setUrl(jenkinsUrl)
    config.save()
    println "Jenkins URL set to: $${jenkinsUrl}"
}
GROOVY

# Create init.groovy.d script to auto-configure webhook triggers for multibranch pipelines
cat > /opt/jenkins/config/init.groovy.d/configure-webhook-triggers.groovy <<'GROOVY'
import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject
import hudson.triggers.Trigger

// Wait for Jenkins to be fully initialized
Jenkins.instance.getItemMap().values().each { item ->
    if (item instanceof WorkflowMultiBranchProject) {
        def jobName = item.name
        
        // Check if webhook trigger already exists
        def triggers = item.getTriggers()
        def hasWebhookTrigger = triggers.values().any { 
            it.class.simpleName.contains('Webhook') || it.class.simpleName.contains('ComputedFolder')
        }
        
        if (!hasWebhookTrigger) {
            try {
                // Use job name (sanitized) as default token
                def token = jobName.replaceAll(/[^a-zA-Z0-9_-]/, '_')
                
                // Instantiate webhook trigger
                def triggerClass = Class.forName('com.igalg.jenkins.plugins.mswt.trigger.ComputedFolderWebHookTrigger')
                def trigger = triggerClass.getConstructor(String.class).newInstance(token)
                
                item.addTrigger(trigger)
                item.save()
                
                println "✓ Configured webhook trigger for '${jobName}' with token: ${token}"
            } catch (Exception e) {
                println "⚠ Failed to configure webhook for '${jobName}': ${e.message}"
            }
        } else {
            println "✓ Webhook trigger already configured for '${jobName}'"
        }
    }
}

println "✓ Webhook trigger configuration complete"
GROOVY

chown -R 1000:1000 /opt/jenkins/config
chmod -R 755 /opt/jenkins/config

# Create agent secrets directory (for nginx to serve)
mkdir -p /opt/jenkins/agent-secrets
chown 1000:1000 /opt/jenkins/agent-secrets
chmod 755 /opt/jenkins/agent-secrets

# Kubernetes agents are ephemeral - no need for static agent monitoring
# This file intentionally left minimal for fast startup

# Create plugin list
cat > /opt/jenkins/config/plugins.txt <<'PLUGINS'
configuration-as-code
docker-workflow
git
workflow-aggregator
slack
credentials
kubernetes
multibranch-scan-webhook-trigger
PLUGINS

DOCKER_BIN="$(command -v docker)"
cd /opt/jenkins

# Remove any old compose.yml if it exists (prefer docker-compose.yml)
[ -f compose.yml ] && rm -f compose.yml

# Verify docker-compose.yml exists
if [ ! -f docker-compose.yml ]; then
  echo "ERROR: docker-compose.yml not found in /opt/jenkins"
  exit 1
fi

# Verify docker is available
if ! "$DOCKER_BIN" ps &>/dev/null; then
  echo "ERROR: Docker daemon is not running or not accessible"
  exit 1
fi

# Start Jenkins with docker compose (with retry logic)
echo "Starting Jenkins with docker compose..."
for attempt in {1..3}; do
  if "$DOCKER_BIN" compose -f docker-compose.yml up -d; then
    echo "Jenkins started successfully"
    
    # Wait for container to be running
    sleep 5
    if "$DOCKER_BIN" ps | grep -q jenkins; then
      echo "Jenkins container is running"
      break
    else
      echo "WARNING: Jenkins container not found after startup (attempt $attempt)"
    fi
  else
    echo "ERROR: docker compose up failed (attempt $attempt/3)"
    if [ $attempt -lt 3 ]; then
      echo "Retrying in 5 seconds..."
      sleep 5
    else
      echo "FATAL: Failed to start Jenkins after 3 attempts"
      exit 1
    fi
  fi
done