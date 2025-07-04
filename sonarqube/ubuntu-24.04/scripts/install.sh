#!/bin/bash
set -euo pipefail

# ========================
# CONFIGURATION
# ========================
# Usa la versión LTS que existe en SonarSource
SONARQUBE_VERSION="9.9.4.87374"
SONARQUBE_USER="sonarqube"
SONARQUBE_GROUP="sonarqube"
SONARQUBE_INSTALL_DIR="/opt/sonarqube"
SONARQUBE_DATA_DIR="/opt/sonarqube/data"

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
log "📦 Installing required dependencies..."
apt-get update
apt-get install -y openjdk-17-jdk unzip wget

# ========================
# CREATE USER AND DIRECTORIES
# ========================
log "👤 Creating SonarQube user and directories..."
id -u $SONARQUBE_USER &>/dev/null || useradd --system --home $SONARQUBE_INSTALL_DIR --shell /bin/bash $SONARQUBE_USER

mkdir -p "$SONARQUBE_INSTALL_DIR"
mkdir -p "$SONARQUBE_DATA_DIR"

# ========================
# DOWNLOAD AND EXTRACT SONARQUBE
# ========================
DOWNLOAD_URL="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
log "⬇️ Downloading SonarQube $SONARQUBE_VERSION..."
wget -qO "/tmp/sonarqube.zip" "$DOWNLOAD_URL"

log "📂 Extracting SonarQube..."
unzip -q "/tmp/sonarqube.zip" -d /opt
rm -f "/tmp/sonarqube.zip"

log "📁 Moving files to installation directory..."
mv "/opt/sonarqube-${SONARQUBE_VERSION}"/* "$SONARQUBE_INSTALL_DIR"
chown -R $SONARQUBE_USER:$SONARQUBE_GROUP "$SONARQUBE_INSTALL_DIR"

# ========================
# CREATE SYSTEMD SERVICE
# ========================
log "🛠 Creating systemd service..."
cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=simple
User=$SONARQUBE_USER
Group=$SONARQUBE_GROUP
PermissionsStartOnly=true
ExecStart=$SONARQUBE_INSTALL_DIR/bin/linux-x86-64/sonar.sh console
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

# ========================
# ENABLE AND START
# ========================
log "🔄 Reloading systemd..."
systemctl daemon-reload

log "🚀 Enabling SonarQube on startup..."
systemctl enable sonarqube

log "▶️ Starting SonarQube..."
systemctl start sonarqube

# ========================
# FINAL INFO
# ========================
log "✅ SonarQube installed and started successfully."
log "🌐 Access SonarQube at: http://<your-server-ip>:9000"
log "💡 Default credentials: admin / admin"