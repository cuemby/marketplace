#!/bin/bash
set -euo pipefail

# ========================
# CONFIGURATION
# ========================
POSTGRES_PASSWORD=""
POSTGRES_USER="odoo"
POSTGRES_DB="postgres"
ODOO_PORT="8069"

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --postgres-password)
      POSTGRES_PASSWORD="$2"
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
# Install Docker if needed
# ========================
if ! command -v docker &> /dev/null; then
  log "🐳 Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

log "🧹 Stopping and removing old containers if already exist..."
sudo docker stop odoo || true
sudo docker stop odoo-db || true
sudo docker rm odoo || true
sudo docker rm odoo-db || true

log "🧹 Removing old volumes if already exist..."
sudo docker volume rm odoo_data || true
sudo docker volume rm odoo_pgdata || true

log "🌐 Creating a new network for our Odoo instance(if not exist)..."
sudo docker network create odoo-net || true

log "🐘 Starting container for the PostgreSQL database..."
sudo docker run -d \
  --name odoo-db \
  --network odoo-net \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -v odoo_pgdata:/var/lib/postgresql/data \
  postgres:15

log "⏳ Waiting for PostgreSQL container to be ready..."
sleep 10

log "📦 Starting container for Odoo..."
sudo docker run -d \
  --name odoo \
  --network odoo-net \
  -p ${ODOO_PORT}:8069 \
  -v odoo_data:/var/lib/odoo \
  -e HOST=odoo-db \
  -e USER="$POSTGRES_USER" \
  -e PASSWORD="$POSTGRES_PASSWORD" \
  odoo:17.0

log "✅ Installation completed."
echo
echo "🌍 To access Odoo, visit:"
echo
echo "   http://$(curl -s ifconfig.me):${ODOO_PORT}"
echo
echo "ℹ️ Username for PostgreSQL container: $POSTGRES_USER"
echo
log "📋 Usa 'sudo docker logs -f odoo' para monitorear el inicio."