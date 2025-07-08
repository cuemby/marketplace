#!/bin/bash
set -euo pipefail

# ========================
# Nextcloud AIO Installer Script
# ========================

# Get public IP
PUBLIC_IP=$(curl -s ifconfig.me)

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

trap 'error "Something went wrong. Aborting."' ERR

log "🌐 Detected Public IP: $PUBLIC_IP"

# ========================
# Install Docker if needed
# ========================
if ! command -v docker &> /dev/null; then
  log "🐳 Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

# ========================
# Stop previous containers if any
# ========================
if sudo docker ps -a --format '{{.Names}}' | grep -q "nextcloud-aio-mastercontainer"; then
  log "🛑 Stopping existing Nextcloud container..."
  sudo docker stop nextcloud-aio-mastercontainer || true
  sudo docker rm nextcloud-aio-mastercontainer || true
fi

# ========================
# Remove volume if desired
# ========================
if sudo docker volume ls | grep -q "nextcloud_aio_mastercontainer"; then
  log "🧹 Removing existing Docker volume..."
  sudo docker volume rm nextcloud_aio_mastercontainer || true
fi

# ========================
# Pull latest image
# ========================
log "⬇️ Pulling Nextcloud AIO latest image..."
sudo docker pull nextcloud/all-in-one:latest

# ========================
# Create volume
# ========================
log "💾 Creating Docker volume..."
sudo docker volume create nextcloud_aio_mastercontainer

# ========================
# Run Nextcloud AIO
# ========================
log "🚀 Starting Nextcloud AIO container..."
sudo docker run -d \
  --name nextcloud-aio-mastercontainer \
  --restart always \
  -p 80:80 \
  -p 8080:8080 \
  -p 8443:8443 \
  -v nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
  -v /var/run/docker.sock:/var/run/docker.sock \
  nextcloud/all-in-one:latest

sleep 5

# ========================
# Show container status
# ========================
log "🔍 Checking container status..."
sudo docker ps

log "✅ Nextcloud AIO has been installed successfully."
echo
echo "🌐 Access the initial setup interface (HTTP) in your browser:"
echo
echo "   http://$PUBLIC_IP:8080"
echo
echo "⚠️ After completing the wizard, access Nextcloud via:"
echo
echo "   https://$PUBLIC_IP:8443"
echo