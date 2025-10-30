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

// Wait for agent node to be created
sleep(5000)

def agentName = "docker"
Computer computer = Jenkins.instance.getComputer(agentName)

if (computer != null) {
    def secret = computer.getJnlpMac()
    
    if (secret) {
        // Write to a file in Jenkins home that can be read by agents
        def secretFile = new File('/var/jenkins_home/agent-secrets/docker-secret.txt')
        secretFile.getParentFile().mkdirs()
        secretFile.text = secret
        
        println "Agent 'docker' secret written to: $${secretFile.absolutePath}"
        println "Agent 'docker' secret: $${secret}"
    } else {
        println "WARNING: Could not get secret for agent 'docker'"
    }
} else {
    println "WARNING: Agent 'docker' not found"
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

"$DOCKER_BIN" compose -f docker-compose.yml up -d