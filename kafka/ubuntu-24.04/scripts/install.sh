#!/bin/bash

set -euo pipefail

# ----- CONFIG -----
KAFKA_VERSION="3.7.0"
SCALA_VERSION="2.13"
KAFKA_USER="kafka"
KAFKA_PORT=9092
INSTALL_DIR="/opt/kafka"
DATA_DIR="/var/lib/kafka"
# -------------------

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
sudo apt-get install -y openjdk-11-jdk curl wget lsb-release

log "👤 Creating kafka user..."
sudo useradd -m -s /bin/bash "${KAFKA_USER}" || true

log "📥 Downloading Kafka ${KAFKA_VERSION}..."
KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
DOWNLOAD_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"
wget -q --show-progress "${DOWNLOAD_URL}" -O "/tmp/${KAFKA_TGZ}"

log "📂 Installing Kafka to ${INSTALL_DIR}..."
sudo mkdir -p "${INSTALL_DIR}"
sudo tar -xzf "/tmp/${KAFKA_TGZ}" --strip-components=1 -C "${INSTALL_DIR}"

log "📁 Creating data directory..."
sudo mkdir -p "${DATA_DIR}"
sudo chown -R "${KAFKA_USER}:${KAFKA_USER}" "${INSTALL_DIR}" "${DATA_DIR}"

# Detect routable public IP
INTERNAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me)

log "📝 Creating systemd unit file..."
sudo tee /etc/systemd/system/kafka.service > /dev/null <<EOF
[Unit]
Description=Apache Kafka Server (KRaft mode)
After=network.target

[Service]
Type=simple
User=${KAFKA_USER}
ExecStart=${INSTALL_DIR}/bin/kafka-server-start.sh ${INSTALL_DIR}/config/kraft/server.properties
ExecStop=${INSTALL_DIR}/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

log "🔧 Configuring KRaft mode server.properties..."
sudo tee ${INSTALL_DIR}/config/kraft/server.properties > /dev/null <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@${INTERNAL_IP}:9093
listeners=PLAINTEXT://0.0.0.0:${KAFKA_PORT},CONTROLLER://${INTERNAL_IP}:9093
advertised.listeners=PLAINTEXT://${PUBLIC_IP}:${KAFKA_PORT}
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
log.dirs=${DATA_DIR}
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
group.initial.rebalance.delay.ms=0
EOF

log "🗄️ Formatting KRaft storage..."
sudo -u "${KAFKA_USER}" ${INSTALL_DIR}/bin/kafka-storage.sh format -t $(uuidgen) -c ${INSTALL_DIR}/config/kraft/server.properties

log "🚀 Enabling and starting Kafka service..."
sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka

# --- Firewall ---
log "🛡️ Configuring firewall rules..."
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow ${KAFKA_PORT}/tcp
elif command -v iptables >/dev/null 2>&1; then
  sudo iptables -C INPUT -p tcp --dport ${KAFKA_PORT} -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport ${KAFKA_PORT} -j ACCEPT
else
  log "⚠️ No firewall tool detected or inactive. Skipping port configuration."
fi

log "✅ Kafka installed and configured successfully!"
log "🔗 Bootstrap server: ${PUBLIC_IP}:${KAFKA_PORT}"