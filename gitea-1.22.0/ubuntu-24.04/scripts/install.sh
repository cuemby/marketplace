#!/usr/bin/env bash
#
# Gitea 1.22.0 Installer on Ubuntu 24.04
# Installation only, no preconfigured setup.

GITEA_VERSION="1.22.0"
GITEA_USER="git"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitea-username)
      GITEA_USER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Prompt for values if not provided
if [[ -z "$GITEA_USER" ]]; then
  read -rp "Gitea user name [git]: " GITEA_USER
fi

# Update system
sudo apt update
sudo apt upgrade -y

# Install dependencies
sudo apt install -y git mariadb-server mariadb-client ufw wget

# Create git user
sudo adduser --system \
             --shell /bin/bash \
             --gecos 'Git Version Control' \
             --group \
             --disabled-password \
             --home /home/${GITEA_USER} \
             ${GITEA_USER}

# Download Gitea
sudo wget -O /usr/local/bin/gitea \
  https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64
sudo chmod +x /usr/local/bin/gitea

# Create directories
sudo mkdir -p /var/lib/gitea/{custom,data,log}
sudo mkdir -p /etc/gitea

# Set permissions
sudo chown -R ${GITEA_USER}:${GITEA_USER} /var/lib/gitea
sudo chown root:${GITEA_USER} /etc/gitea
sudo chmod -R 750 /var/lib/gitea
sudo chmod 770 /etc/gitea

# Configure systemd service
sudo tee /etc/systemd/system/gitea.service > /dev/null <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
Type=simple
User=${GITEA_USER}
Group=${GITEA_USER}
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --work-path /var/lib/gitea
Restart=always
Environment=USER=${GITEA_USER} HOME=/home/${GITEA_USER}

[Install]
WantedBy=multi-user.target
EOF

# Enable service and firewall
sudo systemctl daemon-reload
sudo systemctl enable --now gitea
sudo ufw allow 3000/tcp
sudo ufw --force enable

echo "-------------------------------------------------------"
echo "Installation completed."
echo "Open in your browser: http://<IP>:3000"
echo "Finish the setup using the web-based configuration wizard."
echo "-------------------------------------------------------"
