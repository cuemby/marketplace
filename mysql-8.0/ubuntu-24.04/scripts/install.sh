#!/bin/bash
set -euo pipefail

# ---------- CONFIG ----------
MYSQL_VERSION="8.0"
MYSQL_APT_CONFIG_DEB="mysql-apt-config_0.8.29-1_all.deb"
DOWNLOAD_URL="https://dev.mysql.com/get/${MYSQL_APT_CONFIG_DEB}"
TEMP_DIR=$(mktemp -d)
DB_USERNAME="{{username}}"
DB_PASSWORD="{{password}}"
ROOT_PASSWORD="{{password}}"
# ----------------------------

log() { echo -e "[\e[32mINFO\e[0m] $1"; }
error_exit() { echo -e "[\e[31mERROR\e[0m] $1" >&2; exit 1; }
trap 'error_exit "Something went wrong. Exiting."' ERR

log "Checking required commands..."
for cmd in curl dpkg apt-get sed; do command -v "$cmd" >/dev/null || error_exit "$cmd is missing."; done

log "Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y lsb-release gnupg

log "Downloading and validating MySQL APT config..."
cd "$TEMP_DIR"
curl -fLO "$DOWNLOAD_URL"
dpkg-deb -I "$MYSQL_APT_CONFIG_DEB" >/dev/null

log "Installing MySQL APT config and server ${MYSQL_VERSION}..."
sudo DEBIAN_FRONTEND=noninteractive dpkg -i "$MYSQL_APT_CONFIG_DEB"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

log "Configuring MySQL to listen on 0.0.0.0..."
MYSQL_CNF=$(sudo find /etc/mysql/ -name 'mysqld.cnf' | head -n 1)
sudo sed -i "s/^\s*bind-address\s*=.*/bind-address = 0.0.0.0/" "$MYSQL_CNF"
sudo systemctl restart mysql
sudo systemctl enable --now mysql

log "Setting root password and creating user '${DB_USERNAME}'..."
sleep 5
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
sudo mysql -uroot -p"${ROOT_PASSWORD}" <<SQL
DROP USER IF EXISTS '${DB_USERNAME}'@'localhost';
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USERNAME}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SELECT user, host FROM mysql.user WHERE user='${DB_USERNAME}';
SQL

log "Configuring firewall for port 3306..."
if command -v ufw >/dev/null && sudo ufw status | grep -q "active"; then
  sudo ufw allow 3306/tcp
elif command -v iptables >/dev/null; then
  sudo iptables -C INPUT -p tcp --dport 3306 -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport 3306 -j ACCEPT
else
  log "Firewall not active or unknown. Skipping."
fi

log "Cleaning up..."
rm -rf "$TEMP_DIR"

log "🎉 MySQL ${MYSQL_VERSION} installed. User '${DB_USERNAME}' can connect remotely."