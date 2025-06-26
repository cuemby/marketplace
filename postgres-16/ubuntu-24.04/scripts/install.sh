#!/bin/bash
set -euo pipefail

# --- CONFIG ---
POSTGRES_VERSION="16"
DB_USERNAME="{username}"
DB_PASSWORD="{password}"
ALLOW_REMOTE_CONNECTIONS=true

log() { echo -e "[\e[32mINFO\e[0m] $1"; }
fail() { echo -e "[\e[31mERROR\e[0m] $1" >&2; exit 1; }
trap 'fail "Something went wrong."' ERR

for cmd in curl apt-get sed; do command -v $cmd >/dev/null || fail "$cmd not found"; done

log "Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y wget gnupg2 lsb-release

log "Adding PostgreSQL repo..."
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
  sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y "postgresql-${POSTGRES_VERSION}"
sudo systemctl enable --now postgresql

if $ALLOW_REMOTE_CONNECTIONS; then
  CFG="/etc/postgresql/${POSTGRES_VERSION}/main"
  sudo sed -i "s/^#listen_addresses = .*/listen_addresses = '*'/" "$CFG/postgresql.conf"
  echo "host all all 0.0.0.0/0 md5" | sudo tee -a "$CFG/pg_hba.conf" > /dev/null
  sudo systemctl restart postgresql
fi

log "Creating user '${DB_USERNAME}'..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USERNAME}') THEN
    CREATE ROLE "${DB_USERNAME}" LOGIN PASSWORD '${DB_PASSWORD}';
    ALTER ROLE "${DB_USERNAME}" CREATEDB;
  END IF;
END \$\$;
EOF

sudo -u postgres psql -c "\du ${DB_USERNAME}"

log "Configuring firewall..."
if command -v ufw >/dev/null && sudo ufw status | grep -q "active"; then
  sudo ufw allow 5432/tcp
elif command -v iptables >/dev/null; then
  sudo iptables -C INPUT -p tcp --dport 5432 -j ACCEPT 2>/dev/null || \
  sudo iptables -A INPUT -p tcp --dport 5432 -j ACCEPT
fi

log "✅ PostgreSQL ${POSTGRES_VERSION} installed. User '${DB_USERNAME}' ready. Remote access enabled."