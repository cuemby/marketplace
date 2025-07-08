#!/bin/bash
set -euo pipefail

# ========================
# CONFIGURACIÓN
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

log "🧹 Deteniendo y eliminando contenedores antiguos si existen..."
sudo docker stop odoo || true
sudo docker stop odoo-db || true
sudo docker rm odoo || true
sudo docker rm odoo-db || true

log "🧹 Eliminando volúmenes antiguos si existen..."
sudo docker volume rm odoo_data || true
sudo docker volume rm odoo_pgdata || true

log "🌐 Creando red Docker dedicada (si no existe)..."
sudo docker network create odoo-net || true

log "🐘 Iniciando contenedor de PostgreSQL..."
sudo docker run -d \
  --name odoo-db \
  --network odoo-net \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -v odoo_pgdata:/var/lib/postgresql/data \
  postgres:15

log "⏳ Esperando que PostgreSQL inicie..."
sleep 10

log "📦 Iniciando contenedor de Odoo..."
sudo docker run -d \
  --name odoo \
  --network odoo-net \
  -p ${ODOO_PORT}:8069 \
  -v odoo_data:/var/lib/odoo \
  -e HOST=odoo-db \
  -e USER="$POSTGRES_USER" \
  -e PASSWORD="$POSTGRES_PASSWORD" \
  odoo:17.0

log "✅ Instalación completada."
echo
echo "🌍 Accede a tu Odoo en:"
echo
echo "   http://$(curl -s ifconfig.me):${ODOO_PORT}"
echo
echo "ℹ️ Usuario de la base de datos: $POSTGRES_USER"
echo "ℹ️ Contraseña de la base de datos: $POSTGRES_PASSWORD"
echo
log "📋 Usa 'sudo docker logs -f odoo' para monitorear el inicio."