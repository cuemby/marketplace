#!/bin/bash
set -euo pipefail

# ==================================
# Default Configuration
# ==================================
CLOUDPANEL_PORT=8443

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

trap 'error "Something went wrong. Aborting."' ERR

# ==================================
# Validate OS
# ==================================
log "🔍 Checking Ubuntu version..."
OS_ID=$(lsb_release -si)
OS_CODENAME=$(lsb_release -sc)

if [[ "$OS_ID" != "Ubuntu" ]]; then
  error "This script supports Ubuntu only."
fi

# ==================================
# Cleanup previous installations
# ==================================
log "🧹 Removing previous installations..."
apt-get remove --purge mysql-server mysql-client mysql-common mysql* nginx cloudpanel* -y || true
apt-get autoremove -y || true
apt-get autoclean || true
rm -rf /etc/mysql /var/lib/mysql /etc/nginx /var/lib/cloudpanel || true
rm -f /etc/apt/sources.list.d/mysql.list || true

# ==================================
# Update and install dependencies
# ==================================
log "📦 Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl gnupg2 software-properties-common lsb-release apt-transport-https ca-certificates

# ==================================
# Import MySQL GPG Key
# ==================================
log "🔑 Importing MySQL GPG key..."
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C

# ==================================
# Add MySQL APT Repo
# ==================================
log "➕ Adding MySQL APT repository..."
echo "deb http://repo.mysql.com/apt/ubuntu focal mysql-8.0" | tee /etc/apt/sources.list.d/mysql.list

# ==================================
# Update Package Lists
# ==================================
log "🔄 Updating package lists..."
apt-get update

# ==================================
# Install CloudPanel (v2.0.x for Ubuntu 24.04)
# ==================================
log "⬇️ Installing CloudPanel v2.0.x (Ubuntu 24.04 compatible)..."
curl -sSL https://installer.cloudpanel.io/ce/v2/install.sh | bash

# ==================================
# Configure Firewall
# ==================================
log "🛡️ Configuring firewall for port $CLOUDPANEL_PORT..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow $CLOUDPANEL_PORT/tcp
elif command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport $CLOUDPANEL_PORT -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport $CLOUDPANEL_PORT -j ACCEPT
else
  log "⚠️ No active firewall detected. Continuing..."
fi

# ==================================
# Enable and Start Nginx
# ==================================
log "🔄 Reloading systemd..."
systemctl daemon-reload

log "🚀 Enabling Nginx to start at boot..."
systemctl enable nginx

log "▶️ Restarting Nginx..."
systemctl restart nginx

# ==================================
# Final Info
# ==================================
log "✅ CloudPanel installed successfully."
log "🌐 Access CloudPanel at: https://<your-server-ip>:$CLOUDPANEL_PORT"
echo -e "\n\033[1;33m⚠️ IMPORTANT:\033[0m Complete the setup via the web interface.\n"