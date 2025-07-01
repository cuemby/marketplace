#!/bin/bash
set -e

# ===========================================
# CONFIGURE YOUR DATABASE CONNECTION HERE
# ===========================================
DB_NAME="{db_name}"
DB_USER="{db_user}"
DB_PASSWORD="{db_password}"
DB_HOST="{db_host}"
DB_PORT="{db_port}"
# ===========================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-name)
      DB_NAME="$2"
      shift 2
      ;;
    --db-user)
      DB_USER="$2"
      shift 2
      ;;
    --db-password)
      DB_PASSWORD="$2"
      shift 2
      ;;
    --db-host)
      DB_HOST="$2"
      shift 2
      ;;
    --db-port)
      DB_PORT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Prompt for values if not provided
if [[ -z "$DB_NAME" ]]; then
  read -rp "Database name: " DB_NAME
fi
if [[ -z "$DB_USER" ]]; then
  read -rp "Database user: " DB_USER
fi
if [[ -z "$DB_PASSWORD" ]]; then
  read -srp "Database password: " DB_PASSWORD
  echo
fi
if [[ -z "$DB_HOST" ]]; then
  read -rp "Database host [localhost]: " DB_HOST
  DB_HOST=${DB_HOST:-localhost}
fi
if [[ -z "$DB_PORT" ]]; then
  read -rp "Database port [3306]: " DB_PORT
  DB_PORT=${DB_PORT:-3306}
fi

WP_URL="https://wordpress.org/latest.tar.gz"
WP_DIR="/var/www/html/wordpress"

# Update packages
echo "Updating the system..."
apt update && apt upgrade -y

# Install Apache, PHP and dependencies (without mysql-server)
echo "Installing Apache, PHP, and dependencies..."
apt install -y apache2 php php-mysql libapache2-mod-php php-cli php-curl php-gd php-xml php-mbstring unzip curl

# Enable Apache on startup
systemctl enable apache2
systemctl start apache2

# Download WordPress
echo "Downloading WordPress..."
cd /tmp
curl -O ${WP_URL}
tar -xzf latest.tar.gz

# Get WordPress version
WP_VERSION=$(grep "\$wp_version =" wordpress/wp-includes/version.php | awk -F"'" '{print $2}')

# Move WordPress to Apache directory
echo "Installing WordPress to ${WP_DIR}..."
mkdir -p ${WP_DIR}
cp -r wordpress/* ${WP_DIR}

# Set permissions
echo "Setting permissions..."
chown -R www-data:www-data ${WP_DIR}
find ${WP_DIR} -type d -exec chmod 755 {} \;
find ${WP_DIR} -type f -exec chmod 644 {} \;

# Create wp-config.php
echo "Setting up wp-config.php..."
cp ${WP_DIR}/wp-config-sample.php ${WP_DIR}/wp-config.php

# Prepare DB_HOST with or without port
if [ -n "$DB_PORT" ]; then
  FULL_DB_HOST="${DB_HOST}:${DB_PORT}"
else
  FULL_DB_HOST="${DB_HOST}"
fi

# Replace connection details
sed -i "s/database_name_here/${DB_NAME}/" ${WP_DIR}/wp-config.php
sed -i "s/username_here/${DB_USER}/" ${WP_DIR}/wp-config.php
sed -i "s/password_here/${DB_PASSWORD}/" ${WP_DIR}/wp-config.php
sed -i "s/localhost/${FULL_DB_HOST}/" ${WP_DIR}/wp-config.php

# Generate security keys
echo "Adding security keys..."
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sed -i "/AUTH_KEY/d" ${WP_DIR}/wp-config.php
sed -i "/SECURE_AUTH_KEY/d" ${WP_DIR}/wp-config.php
sed -i "/LOGGED_IN_KEY/d" ${WP_DIR}/wp-config.php
sed -i "/NONCE_KEY/d" ${WP_DIR}/wp-config.php
sed -i "/AUTH_SALT/d" ${WP_DIR}/wp-config.php
sed -i "/SECURE_AUTH_SALT/d" ${WP_DIR}/wp-config.php
sed -i "/LOGGED_IN_SALT/d" ${WP_DIR}/wp-config.php
sed -i "/NONCE_SALT/d" ${WP_DIR}/wp-config.php
echo "$SALT" >> ${WP_DIR}/wp-config.php

# Enable HTTP and HTTPS ports in UFW
echo "Enabling firewall ports..."
ufw allow OpenSSH
ufw allow 'Apache Full'
ufw --force enable

# Restart Apache
systemctl restart apache2

# Final output
echo "=============================================="
echo "Installation completed."
echo "WordPress version: ${WP_VERSION}"
echo "WordPress directory: ${WP_DIR}"
echo "Database name: ${DB_NAME}"
echo "Database user: ${DB_USER}"
echo "Database host: ${FULL_DB_HOST}"
echo "=============================================="