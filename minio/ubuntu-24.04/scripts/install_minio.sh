#!/bin/bash
set -euo pipefail

# ========================
# INITIAL CONFIGURATION
# ========================
MINIO_VERSION="latest"
MINIO_USER="minio-user"
MINIO_GROUP="minio-user"
MINIO_DATA_DIR="/mnt/minio-data"
MINIO_BIN_DIR="/usr/local/bin"
MINIO_CONFIG_DIR="/etc/minio"
MINIO_ROOT_USER=""
MINIO_ROOT_PASSWORD=""

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --minio-root-user)
      MINIO_ROOT_USER="$2"
      shift 2
      ;;
    --minio-root-pass)
      MINIO_ROOT_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# --- Prompt for password if not provided ---
if [[ -z "$MINIO_ROOT_USER" ]]; then
  read -srp "🔑 Root user: " MINIO_ROOT_USER
  echo
fi

# --- Prompt for password if not provided ---
if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
  read -srp "🔑 Root password: " MINIO_ROOT_PASSWORD
  echo
fi

# --- Prompt for credentials if not provided ---
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
apt-get install -y curl wget

# ========================
# CREATING USER AND DIRECTORIES
# ========================
log "👤 Creating MinIO user and directories..."
id -u $MINIO_USER &>/dev/null || useradd --system --home $MINIO_DATA_DIR --shell /bin/false $MINIO_USER

mkdir -p "$MINIO_DATA_DIR"
mkdir -p "$MINIO_CONFIG_DIR"
chown -R $MINIO_USER:$MINIO_GROUP "$MINIO_DATA_DIR"
chown -R $MINIO_USER:$MINIO_GROUP "$MINIO_CONFIG_DIR"
chmod 750 "$MINIO_DATA_DIR"

# ========================
# DOWNLOADING MINIO
# ========================
log "⬇️ Downloading MinIO server binary..."
wget -qO "$MINIO_BIN_DIR/minio" https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x "$MINIO_BIN_DIR/minio"

# ========================
# CREATING SYSTEMD SERVICE
# ========================
log "🛠 Creating systemd service..."
cat > /etc/systemd/system/minio.service <<EOF
[Unit]
Description=MinIO Object Storage
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=$MINIO_USER
Group=$MINIO_GROUP
Environment="MINIO_VOLUMES=$MINIO_DATA_DIR"
Environment="MINIO_ROOT_USER=$MINIO_ROOT_USER"
Environment="MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD"
ExecStart=$MINIO_BIN_DIR/minio server \$MINIO_VOLUMES --console-address ":9001"
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ========================
# ENABLE AND START
# ========================
log "🔄 Reloading systemd..."
systemctl daemon-reload

log "🚀 Enabling MinIO on startup..."
systemctl enable minio

log "▶️ Starting MinIO..."
systemctl start minio

# ========================
# FINAL INFO
# ========================
log "✅ MinIO installed and configured successfully."
log "🌐 The API is available on port 9000 and the Console on port 9001."
log "💡 Default credentials:"
echo -e "\033[1;34m  User: $MINIO_ROOT_USER\033[0m"
echo -e "\033[1;34m  Password: $MINIO_ROOT_PASSWORD\033[0m"