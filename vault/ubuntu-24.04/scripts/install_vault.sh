#!/bin/bash
set -euo pipefail

# ========================
# CONFIGURACIÓN INICIAL
# ========================
VAULT_VERSION="latest"
VAULT_USER="vault"
VAULT_GROUP="vault"
VAULT_DATA_DIR="/opt/vault/data"
VAULT_CONFIG_DIR="/etc/vault.d"

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

trap 'error "Algo salió mal. Abortando."' ERR

# ========================
# DEPENDENCIAS
# ========================
log "📦 Instalando dependencias necesarias..."
apt-get update
apt-get install -y curl gpg apt-transport-https software-properties-common unzip

# ========================
# REPOSITORIO HASHICORP
# ========================
log "🔐 Agregando repositorio de HashiCorp..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

apt-get update

# ========================
# INSTALAR VAULT
# ========================
log "⬇️ Instalando Vault..."
apt-get install -y vault=$VAULT_VERSION || apt-get install -y vault

# ========================
# CREAR USUARIO Y DIRECTORIOS
# ========================
log "👤 Creando usuario y directorios de Vault..."
id -u $VAULT_USER &>/dev/null || useradd --system --home $VAULT_DATA_DIR --shell /bin/false $VAULT_USER

mkdir -p "$VAULT_DATA_DIR"
mkdir -p "$VAULT_CONFIG_DIR"
chown -R $VAULT_USER:$VAULT_GROUP "$VAULT_DATA_DIR"
chown -R $VAULT_USER:$VAULT_GROUP "$VAULT_CONFIG_DIR"
chmod 750 "$VAULT_DATA_DIR"

# ========================
# CONFIGURACIÓN DE VAULT
# ========================
log "⚙️ Creando archivo de configuración predeterminado..."
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
log "🛠 Configurando servicio systemd..."
cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target

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
# HABILITAR Y ARRANCAR
# ========================
log "🔄 Recargando systemd..."
systemctl daemon-reload

log "🚀 Habilitando Vault al iniciar..."
systemctl enable vault

log "▶️ Iniciando Vault..."
systemctl start vault

# ========================
# EXPORTAR VAULT_ADDR
# ========================
echo 'export VAULT_ADDR="http://127.0.0.1:8200"' >> /etc/profile.d/vault.sh
chmod +x /etc/profile.d/vault.sh

log "✅ Vault instalado y configurado correctamente."
log "🌐 Puedes verificar con: systemctl status vault"
log "💡 Para inicializar Vault, ejecuta: vault operator init"