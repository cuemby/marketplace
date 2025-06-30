#!/bin/bash

set -euo pipefail

# ----- CONFIG -----
RABBITMQ_USER=""
RABBITMQ_PASSWORD=""
RABBITMQ_PORT=5672
MANAGEMENT_PORT=15672
# -------------------

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rabbitmq-user)
      RABBITMQ_USER="$2"
      shift 2
      ;;
    --rabbitmq-pass)
      RABBITMQ_PASSWORD="$2"
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
trap 'error_exit "Something went wrong. Exiting."' ERR

log "📦 Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y curl gnupg apt-transport-https ca-certificates lsb-release

# --- Erlang ---
log "📥 Adding RabbitMQ Erlang repository..."
echo "deb [signed-by=/usr/share/keyrings/rabbitmq-erlang.gpg] https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main" | \
  sudo tee /etc/apt/sources.list.d/rabbitmq-erlang.list > /dev/null

log "🔐 Adding Erlang GPG key..."
curl -fsSL https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-erlang/gpg.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/rabbitmq-erlang.gpg

# --- RabbitMQ ---
log "📥 Adding RabbitMQ server repository..."
echo "deb [signed-by=/usr/share/keyrings/rabbitmq-server.gpg] https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-server/deb/ubuntu jammy main" | \
  sudo tee /etc/apt/sources.list.d/rabbitmq-server.list > /dev/null

log "🔐 Adding RabbitMQ GPG key..."
curl -fsSL https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-server/gpg.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/rabbitmq-server.gpg

# --- Install RabbitMQ and Erlang ---
log "🔄 Updating repositories..."
sudo apt-get update -y

log "⬇️ Installing Erlang and RabbitMQ..."
sudo apt-get install -y rabbitmq-server

log "🚀 Enabling and starting RabbitMQ service..."
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

log "📈 Enabling RabbitMQ management plugin..."
sudo rabbitmq-plugins enable rabbitmq_management

log "👤 Creating admin user '${RABBITMQ_USER}'..."
sudo rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}" || true
sudo rabbitmqctl set_user_tags "${RABBITMQ_USER}" administrator
sudo rabbitmqctl set_permissions -p / "${RABBITMQ_USER}" ".*" ".*" ".*"

# --- Firewall ---
log "🛡️ Configuring firewall rules..."
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow ${RABBITMQ_PORT}/tcp
  sudo ufw allow ${MANAGEMENT_PORT}/tcp
elif command -v iptables >/dev/null 2>&1; then
  sudo iptables -C INPUT -p tcp --dport ${RABBITMQ_PORT} -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport ${RABBITMQ_PORT} -j ACCEPT
  sudo iptables -C INPUT -p tcp --dport ${MANAGEMENT_PORT} -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport ${MANAGEMENT_PORT} -j ACCEPT
else
  log "⚠️ No firewall tool detected or inactive. Skipping port configuration."
fi

# --- Access info ---
PUBLIC_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
log "✅ RabbitMQ installed and configured successfully!"
log "🔗 Web UI:     http://${PUBLIC_IP}:${MANAGEMENT_PORT}/ (user: ${RABBITMQ_USER})"
log "📡 AMQP URI:   amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${PUBLIC_IP}:${RABBITMQ_PORT}/"