#!/bin/bash
set -e

# ===========================================
# CONFIGURE YOUR VARIABLES HERE
# ===========================================
DATABASE="{{database}}"          # "internal" to install local MySQL, "external" to use another server

DB_NAME="{{db_name}}"
DB_USER="{{db_user}}"
DB_PASSWORD="{{db_password}}"

# If DATABASE="external", configure host and port here
DB_HOST="{{db_host}}" # Leave empty if not using an external database
DB_PORT="{{db_port}}" # Leave empty if not using an external database
# ===========================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-database)
      DATABASE="$2"
      shift 2
      ;;
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
if [[ -z "$DATABASE" ]]; then
  read -rp "Database transport [internal/external]: " DATABASE
fi
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

# Solo pedir DB_HOST y DB_PORT si DATABASE es external
if [[ "$DATABASE" == "external" ]]; then
  if [[ -z "$DB_HOST" ]]; then
    read -rp "Database host [localhost]: " DB_HOST
    DB_HOST=${DB_HOST:-localhost}
  fi
  if [[ -z "$DB_PORT" ]]; then
    read -rp "Database port [3306]: " DB_PORT
    DB_PORT=${DB_PORT:-3306}
  fi
fi

WP_URL="https://wordpress.org/latest.tar.gz"
WP_DIR="/var/www/html/wordpress"

# Validate DATABASE variable
if [ "$DATABASE" != "internal" ] && [ "$DATABASE" != "external" ]; then
  echo "ERROR: DATABASE must be 'internal' or 'external'."
  exit 1
fi

# If external, validate that DB_HOST is set
if [ "$DATABASE" == "external" ]; then
  if [ -z "$DB_HOST" ]; then
    echo "ERROR: You must define DB_HOST if DATABASE='external'."
    exit 1
  fi
fi

# Update packages
echo "Updating the system..."
sudo apt update && apt upgrade -y

# Install Apache, PHP, and dependencies
echo "Installing Apache, PHP, and dependencies..."
sudo apt install -y apache2 php php-mysql libapache2-mod-php php-cli php-curl php-gd php-xml php-mbstring unzip curl

# Install and configure MySQL if internal
if [ "$DATABASE" == "internal" ]; then
  echo "Installing MySQL..."
  sudo apt install -y mysql-server
  sudo systemctl enable mysql
  sudo systemctl start mysql

  echo "Creating database and user..."
  mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
  mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  DB_HOST="localhost"
  DB_PORT=""
fi

# Prepare full DB host
if [ -n "$DB_PORT" ]; then
  FULL_DB_HOST="${DB_HOST}:${DB_PORT}"
else
  FULL_DB_HOST="${DB_HOST}"
fi

# Enable Apache on boot
sudo systemctl enable apache2
sudo systemctl start apache2

# Download WordPress
echo "Downloading WordPress..."
cd /tmp
sudo curl -O ${WP_URL}
sudo tar -xzf latest.tar.gz

# Get WordPress version
WP_VERSION=$(grep "\$wp_version =" wordpress/wp-includes/version.php | awk -F"'" '{print $2}')

# Move WordPress
echo "Installing WordPress in ${WP_DIR}..."
sudo mkdir -p ${WP_DIR}
sudo cp -r wordpress/* ${WP_DIR}

# Set permissions
chown -R www-data:www-data ${WP_DIR}
find ${WP_DIR} -type d -exec chmod 755 {} \;
find ${WP_DIR} -type f -exec chmod 644 {} \;

# wp-config.php
echo "Configuring wp-config.php..."
sudo cp ${WP_DIR}/wp-config-sample.php ${WP_DIR}/wp-config.php
sudo sed -i "s/database_name_here/${DB_NAME}/" ${WP_DIR}/wp-config.php
sudo sed -i "s/username_here/${DB_USER}/" ${WP_DIR}/wp-config.php
sudo sed -i "s/password_here/${DB_PASSWORD}/" ${WP_DIR}/wp-config.php
sudo sed -i "s/localhost/${FULL_DB_HOST}/" ${WP_DIR}/wp-config.php

# Security keys
echo "Adding security keys..."
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sudo sed -i "/AUTH_KEY/d" ${WP_DIR}/wp-config.php
sudo sed -i "/SECURE_AUTH_KEY/d" ${WP_DIR}/wp-config.php
sudo sed -i "/LOGGED_IN_KEY/d" ${WP_DIR}/wp-config.php
sudo sed -i "/NONCE_KEY/d" ${WP_DIR}/wp-config.php
sudo sed -i "/AUTH_SALT/d" ${WP_DIR}/wp-config.php
sudo sed -i "/SECURE_AUTH_SALT/d" ${WP_DIR}/wp-config.php
sudo sed -i "/LOGGED_IN_SALT/d" ${WP_DIR}/wp-config.php
sudo sed -i "/NONCE_SALT/d" ${WP_DIR}/wp-config.php
echo "$SALT" >> ${WP_DIR}/wp-config.php

# Enable ports in UFW
echo "Enabling ports in the firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Apache Full'
sudo ufw --force enable

# Restart Apache
sudo systemctl restart apache2

# Show information
echo "=============================================="
echo "Installation completed."
echo "WordPress version: ${WP_VERSION}"
echo "WordPress directory: ${WP_DIR}"
echo "Database transport: ${DATABASE}"
echo "Database name: ${DB_NAME}"
echo "DB user: ${DB_USER}"
echo "DB host: ${FULL_DB_HOST}"
echo "=============================================="
