#!/bin/bash
set -euo pipefail

# ========================
# INITIAL CONFIGURATION
# ========================
VAULT_VERSION="latest"
VAULT_USER="vault"
VAULT_GROUP="vault"
VAULT_DATA_DIR="/opt/vault/data"
VAULT_CONFIG_DIR="/etc/vault.d"
TOKEN_FILE="/root/vault_init.txt"
ROOT_TOKEN=""

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

trap 'error "Something went wrong. Aborting."' ERR

# ========================
# PARSE CLI ARGUMENTS
# ========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-token)
      ROOT_TOKEN="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$ROOT_TOKEN" ]]; then
  error "You must pass --root-token <token>"
fi

# ========================
# DEPENDENCIES
# ========================
log "📦 Installing required dependencies..."
apt-get update
apt-get install -y curl gpg apt-transport-https software-properties-common unzip jq

# ========================
# HASHICORP REPO
# ========================
log "🔐 Adding HashiCorp repository..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
apt-get update

# ========================
# INSTALL VAULT
# ========================
log "⬇️ Installing Vault..."
apt-get install -y vault=$VAULT_VERSION || apt-get install -y vault

# ========================
# CREATE USER AND DIRECTORIES
# ========================
log "👤 Creating Vault user and directories..."
id -u $VAULT_USER &>/dev/null || useradd --system --home $VAULT_DATA_DIR --shell /bin/false $VAULT_USER

mkdir -p "$VAULT_DATA_DIR"
mkdir -p "$VAULT_CONFIG_DIR"
chown -R $VAULT_USER:$VAULT_GROUP "$VAULT_DATA_DIR"
chown -R $VAULT_USER:$VAULT_GROUP "$VAULT_CONFIG_DIR"
chmod 750 "$VAULT_DATA_DIR"

# ========================
# VAULT CONFIGURATION
# ========================
log "⚙️ Creating default configuration file..."
cat > "$VAULT_CONFIG_DIR/vault.hcl" <<EOF
storage "file" {
  path = "$VAULT_DATA_DIR"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

ui = true
EOF

chown $VAULT_USER:$VAULT_GROUP "$VAULT_CONFIG_DIR/vault.hcl"
chmod 640 "$VAULT_CONFIG_DIR/vault.hcl"

# ========================
# SYSTEMD SERVICE
# ========================
log "🛠 Configuring systemd service..."
cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=HashiCorp Vault
After=network-online.target
Requires=network-online.target

[Service]
User=$VAULT_USER
Group=$VAULT_GROUP
ExecStart=/usr/bin/vault server -config=$VAULT_CONFIG_DIR/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ========================
# ENABLE AND START
# ========================
log "🔄 Reloading systemd..."
systemctl daemon-reload
log "🚀 Enabling Vault..."
systemctl enable vault
log "▶️ Starting Vault..."
systemctl start vault

# Wait for vault to be up
sleep 5

# ========================
# EXPORT VAULT_ADDR
# ========================
export VAULT_ADDR="http://127.0.0.1:8200"
log "🌐 VAULT_ADDR=$VAULT_ADDR"

# ========================
# INITIALIZE VAULT
# ========================
log "🔑 Initializing Vault..."
INIT_OUTPUT=$(vault operator init -format=json)

# Save keys to file
echo "$INIT_OUTPUT" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
log "💾 Initialization keys saved to $TOKEN_FILE"

# Parse keys
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

# ========================
# UNSEAL VAULT
# ========================
log "🔓 Unsealing Vault with required keys..."
for i in 0 1 2; do
  KEY=$(echo "$INIT_OUTPUT" | jq -r ".unseal_keys_b64[$i]")
  vault operator unseal "$KEY"
done

# ========================
# LOGIN WITH INITIAL ROOT TOKEN
# ========================
INIT_ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
export VAULT_TOKEN="$INIT_ROOT_TOKEN"

# ========================
# CREATE CUSTOM ROOT TOKEN
# ========================
log "🪪 Creating user-specified root token..."
vault token create -id="$ROOT_TOKEN" -policy="root"

log "✅ Vault installed, initialized, and unsealed."
log "🔐 Custom root token: $ROOT_TOKEN"
log "💾 Unseal key stored in: $TOKEN_FILE"