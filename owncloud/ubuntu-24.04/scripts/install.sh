#!/bin/bash
set -euo pipefail

# ========================
# CONFIGURATION
# ========================
OWNCLOUD_PORT="8080"
DB_ROOT_PASSWORD=""
DB_USER="owncloud"
DB_PASSWORD=""
DB_NAME="owncloud"

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-root-password)
      DB_ROOT_PASSWORD="$2"
      shift 2
      ;;
    --db-password)
      DB_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$DB_ROOT_PASSWORD" || -z "$DB_PASSWORD" ]]; then
  echo "[ERROR] --db-root-password and --db-password are required."
  exit 1
fi

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}
trap 'error "Something went wrong. Aborting."' ERR

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
# Stop and remove old containers
# ========================
log "🧹 Stopping and removing old containers..."
sudo docker stop owncloud || true
sudo docker stop owncloud-db || true
sudo docker rm owncloud || true
sudo docker rm owncloud-db || true

log "🧹 Removing old volumes..."
sudo docker volume rm owncloud_data || true
sudo docker volume rm owncloud_dbdata || true

# ========================
# Create Docker network
# ========================
log "🌐 Creating Docker network..."
sudo docker network create owncloud-net || true

# ========================
# Start MariaDB container
# ========================
log "🐘 Starting MariaDB container..."
sudo docker run -d \
  --name owncloud-db \
  --network owncloud-net \
  -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
  -e MYSQL_DATABASE="$DB_NAME" \
  -e MYSQL_USER="$DB_USER" \
  -e MYSQL_PASSWORD="$DB_PASSWORD" \
  -v owncloud_dbdata:/var/lib/mysql \
  mariadb:10.11 \
  --transaction-isolation=READ-COMMITTED \
  --binlog-format=ROW

log "⏳ Waiting for MariaDB to initialize..."
sleep 20

PUBLIC_IP=$(curl -s ifconfig.me)
# ========================
# Start ownCloud container
# ========================
log "📦 Starting ownCloud container..."
sudo docker run -d \
  --name owncloud \
  --network owncloud-net \
  -p ${OWNCLOUD_PORT}:8080 \
  -e OWNCLOUD_DB_TYPE=mysql \
  -e OWNCLOUD_DB_NAME="$DB_NAME" \
  -e OWNCLOUD_DB_USERNAME="$DB_USER" \
  -e OWNCLOUD_DB_PASSWORD="$DB_PASSWORD" \
  -e OWNCLOUD_DB_HOST="owncloud-db" \
  -e OWNCLOUD_TRUSTED_DOMAINS="$PUBLIC_IP" \
  -v owncloud_data:/var/www/html \
  owncloud/server:10.15.3

# ========================
# Done
# ========================
log "✅ ownCloud is up and running!"
echo
echo "🌍 Access ownCloud at:"
echo
echo "   http://${INTERNAL_IP}:${OWNCLOUD_PORT}"
echo
log "📝 MariaDB credentials:"
echo
echo "   User: $DB_USER"
echo "   Password: $DB_PASSWORD"
echo
log "📋 Use 'sudo docker logs -f owncloud' to monitor logs."