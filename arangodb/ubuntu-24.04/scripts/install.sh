#!/bin/bash

set -e

ARANGODB_PASSWORD=""

# ========================
# Parse CLI args
# ========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arangodb-pass)
      ARANGODB_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "[INFO] Verifiying Docker..."
if ! command -v docker &> /dev/null; then
    echo "[INFO] Docker not found. Installing Docker..."
    apt-get update
    apt-get install -y docker.io
    systemctl enable --now docker
else
    echo "[INFO] Docker is already installed."
fi

echo "[INFO] Creating network and volumes for ArangoDB..."
docker network create arango-net || true
docker volume create arango-data || true

echo "[INFO] Downloading official image of ArangoDB..."
docker pull arangodb:latest

echo "[INFO] Starting container for ArangoDB..."
docker run -d \
  --name arangodb \
  --restart always \
  --network arango-net \
  -p 8529:8529 \
  -e ARANGO_ROOT_PASSWORD=${ARANGODB_PASSWORD} \
  -v arango-data:/var/lib/arangodb3 \
  arangodb:latest

echo "[INFO] Complete installation."
echo "------------------------------------------"
echo "Link to UI: http://<IP_SERVIDOR>:8529"
echo "User: root"
echo "------------------------------------------"