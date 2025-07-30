#!/bin/bash
set -euo pipefail

# ========================
# CONFIG
# ========================
KEYCLOAK_VERSION="24.0.4"
KEYCLOAK_URL="https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
KEYCLOAK_DIR="/opt/keycloak"
ADMIN_USER=""
ADMIN_PASSWORD=""
PUBLIC_IP=$(curl -s ifconfig.me)
log() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }
trap 'error "Something went wrong. Aborting."' ERR

# ========================
# Parse CLI args
# ========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-user)
      ADMIN_USER="$2"
      shift 2
      ;;
    --admin-pass)
      ADMIN_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ========================
# Dependencies
# ========================
log "📦 Install dependencies..."
apt-get update
apt-get install -y curl tar wget unzip openjdk-21-jre-headless openssl

# ========================
# Keycloak user
# ========================
if ! id "keycloak" &>/dev/null; then
  log "👤 Creating user keycloak..."
  useradd --system --create-home --shell /bin/false keycloak
fi

# ========================
# Downloading Keycloak
# ========================
log "⬇️ Downloading Keycloak..."
wget -O /tmp/keycloak.tar.gz "${KEYCLOAK_URL}"

log "📂 Extracting Keycloak..."
mkdir -p "${KEYCLOAK_DIR}"
tar -xzf /tmp/keycloak.tar.gz -C /opt/
mv /opt/keycloak-${KEYCLOAK_VERSION}/* "${KEYCLOAK_DIR}/"

# ========================
# Autosign certificate
# ========================
log "🔐 Generating autosigned certificate..."
mkdir -p ${KEYCLOAK_DIR}/certs
openssl req -x509 -newkey rsa:2048 -keyout ${KEYCLOAK_DIR}/certs/key.pem -out ${KEYCLOAK_DIR}/certs/cert.pem -days 365 -nodes \
  -subj "/CN=$(hostname -I | awk '{print $1}')/OU=IT/O=MyCompany/L=City/ST=State/C=US"
chown -R keycloak:keycloak ${KEYCLOAK_DIR}

# ========================
# CREATE ADMIN USER
# ========================
log "👤 Creating admin user..."
export KEYCLOAK_ADMIN=${ADMIN_USER}
export KEYCLOAK_ADMIN_PASSWORD=${ADMIN_PASSWORD}

# ========================
# BUILD OPTIMIZED (No HTTPS)
# ========================
log "🔧 Compiling Keycloak optimized version..."
sudo -u keycloak ${KEYCLOAK_DIR}/bin/kc.sh build --db=dev-file

# ========================
# SERVICE SYSTEMD
# ========================
log "⚙️ Creating systemd service..."
cat >/etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak
After=network.target

[Service]
User=keycloak
Group=keycloak
Environment=KEYCLOAK_ADMIN=${ADMIN_USER}
Environment=KEYCLOAK_ADMIN_PASSWORD=${ADMIN_PASSWORD}
ExecStart=${KEYCLOAK_DIR}/bin/kc.sh start-dev \
  --https-certificate-file=${KEYCLOAK_DIR}/certs/cert.pem \
  --https-certificate-key-file=${KEYCLOAK_DIR}/certs/key.pem \
  --hostname=${PUBLIC_IP}
Restart=always
LimitNOFILE=102642

[Install]
WantedBy=multi-user.target
EOF

# ========================
# ACTIVE SERVICE
# ========================
log "🔄 Reloading daemon systemd..."
systemctl daemon-reload
systemctl enable keycloak
systemctl restart keycloak

log "✅ Complete installation!"
echo "🌍 Link to: ${PUBLIC_IP}:8443"
echo "   User: ${ADMIN_USER}"
