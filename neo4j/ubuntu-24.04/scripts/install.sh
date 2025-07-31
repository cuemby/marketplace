#!/bin/bash
set -e

PASSWORD=""

# ========================
# Parse CLI args
# ========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "[INFO] Install dependencies Docker..."
if ! command -v docker &> /dev/null
then
    apt-get update && apt-get install -y docker.io docker-compose
    systemctl enable --now docker
fi

echo "[INFO] Creating persistence directory..."
mkdir -p /opt/neo4j/data /opt/neo4j/logs /opt/neo4j/conf /opt/neo4j/plugins

echo "[INFO] Creating docker-compose file..."
cat <<EOF > /opt/neo4j/docker-compose.yml
version: '3'
services:
  neo4j:
    image: neo4j:5
    container_name: neo4j
    environment:
      - NEO4J_AUTH=neo4j/${PASSWORD}
    ports:
      - "7474:7474"
      - "7687:7687"
    volumes:
      - /opt/neo4j/data:/data
      - /opt/neo4j/logs:/logs
      - /opt/neo4j/conf:/conf
      - /opt/neo4j/plugins:/plugins
    restart: unless-stopped
EOF

echo "[INFO] Starting Neo4j..."
cd /opt/neo4j
docker-compose up -d

echo "[INFO] Neo4j Successfully installation"
echo "--------------------------------------"
echo " UI Web: http://<TU-IP>:7474"
echo " User: neo4j"
echo "--------------------------------------"