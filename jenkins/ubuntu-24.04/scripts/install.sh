#!/bin/bash
set -euo pipefail

# ========================
# DEFAULT CONFIGURATION
# ========================
JENKINS_PORT=8080
ADMIN_USER=""
ADMIN_PASSWORD=""

# ========================
# PARSE CLI ARGUMENTS
# ========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-user)
      ADMIN_USER="$2"
      shift 2
      ;;
    --admin-password)
      ADMIN_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

trap 'error "Something went wrong. Aborting."' ERR

# ========================
# DEPENDENCIES
# ========================
log "📦 Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl gnupg2 software-properties-common openjdk-17-jdk

# ========================
# ADD JENKINS REPO
# ========================
log "🔐 Adding Jenkins repository and GPG key..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor -o /usr/share/keyrings/jenkins.gpg

echo "deb [signed-by=/usr/share/keyrings/jenkins.gpg] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list

apt-get update

# ========================
# INSTALL JENKINS
# ========================
log "⬇️ Installing Jenkins..."
apt-get install -y jenkins

# ========================
# CONFIGURE FIREWALL
# ========================
log "🛡️ Checking firewall configuration to allow port $JENKINS_PORT..."

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  log "⚙️ ufw detected. Allowing port $JENKINS_PORT..."
  ufw allow $JENKINS_PORT/tcp
elif command -v iptables >/dev/null 2>&1; then
  log "⚙️ iptables detected. Adding rule for port $JENKINS_PORT..."
  iptables -C INPUT -p tcp --dport $JENKINS_PORT -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport $JENKINS_PORT -j ACCEPT
else
  log "⚠️ No active firewall detected. Continuing..."
fi

# ========================
# DISABLE SETUP WIZARD
# ========================
log "⚙️ Disabling Jenkins setup wizard..."
echo 'JAVA_ARGS="-Djenkins.install.runSetupWizard=false"' > /etc/default/jenkins

# ========================
# CREATE INIT GROOVY SCRIPT
# ========================
log "📝 Creating Groovy init script to set admin credentials..."
mkdir -p /var/lib/jenkins/init.groovy.d

cat > /var/lib/jenkins/init.groovy.d/basic-security.groovy <<EOF
#!groovy

import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

println "--> Creating local user '${ADMIN_USER}'"

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("${ADMIN_USER}", "${ADMIN_PASSWORD}")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
EOF

chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d

# ========================
# ENABLE AND START
# ========================
log "🔄 Reloading systemd..."
systemctl daemon-reload

log "🚀 Enabling Jenkins to start at boot..."
systemctl enable jenkins

log "▶️ Starting Jenkins..."
systemctl restart jenkins

# ========================
# FINAL INFO
# ========================
log "✅ Jenkins installed and configured successfully."
log "🌐 Access Jenkins at: http://<your-server-ip>:$JENKINS_PORT"
log "🔑 Login with:"
echo -e "\n  Username: \033[1;34m${ADMIN_USER}\033[0m"
echo -e "  Password: \033[1;34m${ADMIN_PASSWORD}\033[0m\n"