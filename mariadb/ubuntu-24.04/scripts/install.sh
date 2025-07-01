#!/bin/bash

set -euo pipefail

# ---------- CONFIG ----------
MARIADB_VERSION="10.6"
DB_USERNAME=""
DB_PASSWORD=""
SET_ROOT_PASSWORD=true
ROOT_PASSWORD=""
MARIADB_PORT=3306
TEMP_DIR=$(mktemp -d)
# ----------------------------

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-password)
      ROOT_PASSWORD="$2"
      shift 2
      ;;
    --db-pass)
      DB_PASSWORD="$2"
      shift 2
      ;;
    --db-user)
      DB_USERNAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log() {
  echo -e "[\e[32mINFO\e[0m] $1"
}

error_exit() {
  echo -e "[\e[31mERROR\e[0m] $1" >&2
  exit 1
}

trap 'error_exit \"Something went wrong. Exiting.\"' ERR

log "📦 Installing MariaDB Server..."
sudo apt-get update -y
sudo apt-get install -y mariadb-server mariadb-client

log "🔄 Starting and enabling MariaDB..."
sudo systemctl enable mariadb
sudo systemctl start mariadb

log "⌛ Waiting for MariaDB to be ready..."
sleep 5

# --- Secure installation ---
if $SET_ROOT_PASSWORD; then
  log "🔐 Setting MariaDB root password and switching auth method..."
  sudo mariadb <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${ROOT_PASSWORD}');
FLUSH PRIVILEGES;
EOF
fi

log "🧹 Removing any conflicting user '${DB_USERNAME}'..."
sudo mariadb -uroot -p"${ROOT_PASSWORD}" -e "DROP USER IF EXISTS '${DB_USERNAME}'@'localhost';"
sudo mariadb -uroot -p"${ROOT_PASSWORD}" -e "DROP USER IF EXISTS '${DB_USERNAME}'@'%';"

log "👤 Creating user '${DB_USERNAME}' with remote access..."
sudo mariadb -uroot -p"${ROOT_PASSWORD}" -e "CREATE USER '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mariadb -uroot -p"${ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO '${DB_USERNAME}'@'%' WITH GRANT OPTION;"
sudo mariadb -uroot -p"${ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

log "🛠 Configuring MariaDB to listen on 0.0.0.0..."
MARIADB_CNF=$(sudo find /etc/mysql/ -name '50-server.cnf' | head -n 1)
sudo sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" "$MARIADB_CNF"

log "🔄 Restarting MariaDB to apply bind-address change..."
sudo systemctl restart mariadb

log "🛡️ Checking firewall configuration to allow remote access on port ${MARIADB_PORT}..."
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  log "ufw detected. Allowing port ${MARIADB_PORT}..."
  sudo ufw allow ${MARIADB_PORT}/tcp
elif command -v iptables >/dev/null 2>&1; then
  log "iptables detected. Adding rule to allow port ${MARIADB_PORT}..."
  sudo iptables -C INPUT -p tcp --dport ${MARIADB_PORT} -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport ${MARIADB_PORT} -j ACCEPT
else
  log "No known firewall tool detected or firewall inactive. Skipping port configuration."
fi

PUBLIC_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
CONN_STR="mariadb://${DB_USERNAME}:${DB_PASSWORD}@${PUBLIC_IP}:${MARIADB_PORT}/"

log "✅ MariaDB ${MARIADB_VERSION} instalado y configurado correctamente."
log "🔗 String de conexión listo para usar:"
echo -e "\n\e[36m$CONN_STR\e[0m\n"

log "🧹 Cleaning up temporary files..."
rm -rf "$TEMP_DIR"