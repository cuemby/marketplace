#!/bin/bash
set -euo pipefail

# ---------- CONFIG ----------
REDIS_PORT=6379
REDIS_PASSWORD="{password}"
ALLOW_REMOTE_CONNECTIONS=true
# ----------------------------

log() {
  echo -e "[\e[32mINFO\e[0m] $1"
}

error_exit() {
  echo -e "[\e[31mERROR\e[0m] $1" >&2
  exit 1
}

trap 'error_exit "Something went wrong. Exiting."' ERR

check_command() {
  command -v "$1" >/dev/null 2>&1 || error_exit "$1 is required but not installed."
}

log "Checking required commands..."
check_command apt-get
check_command sed
check_command systemctl

log "Updating package index..."
sudo apt-get update -y

log "Installing Redis server..."
sudo apt-get install -y redis-server

log "Enabling Redis to start on boot..."
sudo systemctl enable redis-server

log "Configuring Redis password..."
sudo sed -i "s/^# requirepass .*$/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf

if $ALLOW_REMOTE_CONNECTIONS; then
  log "Allowing Redis to accept remote connections..."

  sudo sed -i "s/^bind 127\.0\.0\.1 -::1/bind 0.0.0.0/" /etc/redis/redis.conf
  sudo sed -i "s/^protected-mode yes/protected-mode no/" /etc/redis/redis.conf
fi

log "Restarting Redis service..."
sudo systemctl restart redis-server

log "Checking firewall configuration to allow remote access on port $REDIS_PORT..."

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  log "ufw detected. Allowing port $REDIS_PORT..."
  sudo ufw allow $REDIS_PORT/tcp
elif command -v iptables >/dev/null 2>&1; then
  log "iptables detected. Adding rule to allow port REDIS_POR..."
  sudo iptables -C INPUT -p tcp --dport $REDIS_PORT -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport $REDIS_PORT -j ACCEPT
else
  log "No known firewall tool detected or firewall inactive. Skipping port configuration."
fi

log "✅ Redis installed and configured at 0.0.0.0:$REDIS_PORT with password."