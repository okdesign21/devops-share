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
      allowAnonymousRead: false
  
unclassified:
  location:
    url: "${jenkins_url}"
    adminAddress: "admin@jenkins.local"

nodes:
  - permanent:
      name: "docker"
      remoteFS: "/home/jenkins/agent"
      launcher:
        inbound:
          webSocket: true
      numExecutors: 2
      labelString: "docker linux"
      mode: EXCLUSIVE
      
security:
  remotingCLI:
    enabled: false
CASC

# Create init script to export agent secret to a file accessible via HTTP
cat > /opt/jenkins/config/init.groovy.d/export-agent-secret.groovy <<'GROOVY'
import jenkins.model.Jenkins
import hudson.model.Computer
import java.io.File

def agentName = "docker"
def maxAttempts = 180  // ~15 minutes (increased from 120)
def attempt = 0
def secret = null

// Wait for Jenkins to be fully initialized
while (!Jenkins.instance.isQuietingDown() && Jenkins.instance.getInitLevel() != hudson.init.InitMilestone.COMPLETED) {
  println "Waiting for Jenkins to complete initialization..."
  Thread.sleep(2000)
}

println "Jenkins initialization complete. Looking for agent '$agentName'..."

while (attempt < maxAttempts && (secret == null || secret.trim().isEmpty())) {
  attempt++
  def computer = Jenkins.instance.getComputer(agentName)
  if (computer != null) {
    secret = computer.getJnlpMac()
    if (secret && !secret.trim().isEmpty()) {
      break
    }
  }
  println "Waiting for agent 'docker' and its secret (attempt $${attempt}/$${maxAttempts})..."
  Thread.sleep(3000)  // Check every 3 seconds instead of 5
}

if (secret && !secret.trim().isEmpty()) {
  def secretFile = new File('/var/jenkins_home/agent-secrets/docker-secret.txt')
  secretFile.getParentFile().mkdirs()
  secretFile.text = secret
  secretFile.setReadable(true, false)  // Make readable by all
  println "✓ Agent 'docker' secret written to: $${secretFile.absolutePath}"
  println "✓ Secret length: $${secret.length()} characters"
} else {
  println "WARNING: Agent 'docker' secret not available after waiting. Agent may not be able to connect."
}
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

chown -R 1000:1000 /opt/jenkins/config
chmod -R 755 /opt/jenkins/config

# Create agent secrets directory (for nginx to serve)
mkdir -p /opt/jenkins/agent-secrets
chown 1000:1000 /opt/jenkins/agent-secrets
chmod 755 /opt/jenkins/agent-secrets

# Create an init script to mark the agent as ONLINE when connected (non-blocking)
cat > /opt/jenkins/config/init.groovy.d/mark-agent-online.groovy <<'GROOVY'
import jenkins.model.Jenkins
import hudson.model.Computer
import java.io.File

def agentName = "docker"

// Run in background thread so Jenkins startup is not blocked
Thread.start {
  def maxAttempts = 120 // ~10 minutes
  def attempt = 0

  File dir = new File('/var/jenkins_home/agent-secrets')
  dir.mkdirs()
  File ready = new File(dir, 'docker-ready')
  File timeout = new File(dir, 'docker-timeout')

  println "Checking agent '$agentName' status in background (non-blocking)..."

  while (attempt < maxAttempts) {
    attempt++
    Computer c = Jenkins.instance.getComputer(agentName)
    if (c != null && !c.isOffline()) {
      ready.text = 'online\n'
      println "Agent '$agentName' is ONLINE. Wrote marker to $${ready.absolutePath}"
      break
    }
    if (attempt % 12 == 0) { // Log every minute
      println "Still waiting for agent '$agentName' (attempt $${attempt}/$${maxAttempts})..."
    }
    Thread.sleep(5000)
  }

  if (!ready.exists()) {
    timeout.text = 'timeout\n'
    println "WARNING: Agent '$agentName' did not become ONLINE within timeout. Wrote $${timeout.absolutePath}"
  }
}

println "Agent monitoring started in background. Jenkins will continue startup."
GROOVY

# Create plugin list
cat > /opt/jenkins/config/plugins.txt <<'PLUGINS'
configuration-as-code
docker-workflow
git
workflow-aggregator
slack
credentials
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