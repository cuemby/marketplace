#!/bin/bash
set -euo pipefail
# ----------------------------------
# Configurable Variables
# ----------------------------------
CASSANDRA_PASSWORD="Admin123"
LISTEN_ADDRESS=$(hostname -I | awk '{print $1}')
CASSANDRA_VERSION="41x"
YAML_FILE="/etc/cassandra/cassandra.yaml"
SEEDS="$LISTEN_ADDRESS"
# ----------------------------------
# Functions
# ----------------------------------
install_dependencies() {
  echo "➤ Installing dependencies..."
  sudo apt-get update
  sudo apt-get install -y gnupg curl lsb-release apt-transport-https net-tools python3-pip python3-six software-properties-common
  sudo apt-get install -y pipx
  sudo pipx ensurepath
  sudo pipx install cqlsh

  export PATH="$HOME/.local/bin:$PATH"
}

add_cassandra_repo() {
  echo "➤ Adding official Cassandra repository..."
  sudo rm -f /usr/share/keyrings/cassandra.gpg
  curl -fsSL https://www.apache.org/dist/cassandra/KEYS | sudo gpg --dearmor -o /usr/share/keyrings/cassandra.gpg
  echo "deb [signed-by=/usr/share/keyrings/cassandra.gpg] https://debian.cassandra.apache.org $CASSANDRA_VERSION main" | sudo tee /etc/apt/sources.list.d/cassandra.list
  sudo apt-get update
}

install_cassandra() {
  echo "➤ Installing Cassandra..."
  sudo apt-get install -y cassandra
}

configure_cassandra() {
  echo "➤ Configuring Cassandra..."
  sudo sed -i "s/^listen_address:.*/listen_address: $LISTEN_ADDRESS/" "$YAML_FILE"
  sudo sed -i "s/^rpc_address:.*/rpc_address: 0.0.0.0/" "$YAML_FILE"

  if grep -q "^# broadcast_rpc_address:" "$YAML_FILE"; then
    sudo sed -i "s|^# broadcast_rpc_address:.*|broadcast_rpc_address: $LISTEN_ADDRESS|" "$YAML_FILE"
  elif grep -q "^broadcast_rpc_address:" "$YAML_FILE"; then
    sudo sed -i "s|^broadcast_rpc_address:.*|broadcast_rpc_address: $LISTEN_ADDRESS|" "$YAML_FILE"
  else
    echo "broadcast_rpc_address: $LISTEN_ADDRESS" | sudo tee -a "$YAML_FILE"
  fi

  # Replace the entire seed_provider block with proper indentation
  sudo awk -v ip="$LISTEN_ADDRESS" '
  BEGIN {skip=0}
  /^seed_provider:/ {
    print "seed_provider:";
    print "    - class_name: org.apache.cassandra.locator.SimpleSeedProvider";
    print "      parameters:";
    print "          - seeds: \"" ip "\"";
    skip=1;
    next
  }
  skip && /^[^[:space:]]/ {skip=0}
  !skip {print}
  ' "$YAML_FILE" | sudo tee "$YAML_FILE.tmp" >/dev/null
  sudo mv "$YAML_FILE.tmp" "$YAML_FILE"
}

enable_firewall() {
  echo "➤ Configuring firewall (ufw)..."
  if ! command -v ufw >/dev/null; then
    sudo apt-get install -y ufw
    sudo ufw allow ssh
    sudo ufw --force enable
  fi
  for port in 7000 7199 9042; do
    if ! sudo ufw status | grep -q "$port/tcp"; then
      sudo ufw allow ${port}/tcp
    fi
  done
}

clean_previous_state() {
  echo "➤ Removing previous data..."
  sudo systemctl stop cassandra || true
  sudo rm -rf /var/lib/cassandra/data/system/*
  sudo rm -rf /var/lib/cassandra/commitlog/*
  sudo rm -rf /var/lib/cassandra/hints/*
  sudo rm -rf /var/lib/cassandra/saved_caches/*
}

restart_cassandra() {
  echo "➤ Restarting Cassandra..."
  sudo systemctl daemon-reload
  sudo systemctl start cassandra
  sudo systemctl enable cassandra
}

wait_for_port_9042() {
  echo "⏳ Waiting for Cassandra to open port 9042..."
  MAX_TRIES=100
  SLEEP_INTERVAL=3
  for ((i=1;i<=MAX_TRIES;i++)); do
    if ss -ltn | grep -q ":9042"; then
      echo "✅ Port 9042 is listening."
      return
    fi
    if ! pgrep -f cassandra >/dev/null; then
      echo "❌ Cassandra is not running. Check logs:"
      echo "  sudo journalctl -u cassandra"
      echo "  sudo tail -f /var/log/cassandra/system.log"
      exit 1
    fi
    sleep "$SLEEP_INTERVAL"
  done
  echo "⚠️ Cassandra did not open port 9042 after $((MAX_TRIES*SLEEP_INTERVAL)) seconds."
  exit 1
}

configure_password_authentication() {
  echo "➤ Enabling PASSWORD authentication..."
  sudo sed -i "s/^authenticator:.*/authenticator: PasswordAuthenticator/" "$YAML_FILE"
  sudo sed -i "s/^authorizer:.*/authorizer: CassandraAuthorizer/" "$YAML_FILE"
}

change_user_password() {
  echo "➤ Changing password for user 'cassandra'..."
  sudo /root/.local/bin/cqlsh $LISTEN_ADDRESS -u cassandra -p cassandra -e "ALTER USER cassandra WITH PASSWORD '$CASSANDRA_PASSWORD';"
}

# ----------------------------------
# Execution
# ----------------------------------
install_dependencies
add_cassandra_repo
install_cassandra
configure_cassandra
enable_firewall
clean_previous_state

# Step 1: Start with AllowAll to avoid authentication on first run
sudo sed -i "s/^authenticator:.*/authenticator: AllowAllAuthenticator/" "$YAML_FILE"
sudo sed -i "s/^authorizer:.*/authorizer: AllowAllAuthorizer/" "$YAML_FILE"

restart_cassandra
wait_for_port_9042

# Step 2: Switch to PasswordAuthenticator
configure_password_authentication
restart_cassandra
wait_for_port_9042

change_user_password
echo "✅ Cassandra is ready at $LISTEN_ADDRESS:9042"
echo "🔐 User 'cassandra' with password: $CASSANDRA_PASSWORD"
echo "ℹ️ You can connect remotely with:"
echo ""
echo "   cqlsh $LISTEN_ADDRESS -u cassandra -p $CASSANDRA_PASSWORD"
