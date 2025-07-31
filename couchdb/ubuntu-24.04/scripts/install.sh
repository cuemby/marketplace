#!/bin/bash
set -euo pipefail

COUCHDB_USER=""
COUCHDB_PASS=""
COUCHDB_PORT=5984
COUCHDB_CONTAINER="couchdb"

log(){ echo -e "\033[1;32m[INFO]\033[0m $1"; }
error(){ echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }
trap 'error "Something went wrong. Aborting."' ERR

# ========================
# Parse CLI args
# ========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --couchdb-user)
      COUCHDB_USER="$2"
      shift 2
      ;;
    --couchdb-pass)
      COUCHDB_PASS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log "Upgrating system..."
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

log "Installing Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
else
  log "Docker is already installed."
fi

log "Starting & enabling Docker..."
sudo systemctl enable --now docker

log "Downloading CouchDB in Docker..."
if sudo docker ps -a --format '{{.Names}}' | grep -q "^${COUCHDB_CONTAINER}$"; then
  log "Remove existing CouchDB container..."
  sudo docker rm -f ${COUCHDB_CONTAINER}
fi

sudo docker run -d \
  --name ${COUCHDB_CONTAINER} \
  -e COUCHDB_USER=${COUCHDB_USER} \
  -e COUCHDB_PASSWORD=${COUCHDB_PASS} \
  -p ${COUCHDB_PORT}:5984 \
  couchdb:3

log "Waiting for CouchDB to start..."
sleep 5

PUBLIC_IP=$(curl -s ifconfig.me)
log "Completed installation of CouchDB."
echo "🌍 Link to CouchDB: http://${PUBLIC_IP}:${COUCHDB_PORT}/_utils/"