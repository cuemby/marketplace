#!/bin/bash
set -euo pipefail

# script vars
VERSION="9.0.0"
ELASTICSEARCH_PASSWORD=""
KIBANA_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --elasticserch-password)
      ELASTICSEARCH_PASSWORD="$2"
      shift 2
      ;;
    --kibana-password)
      KIBANA_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Prompt for values if not provided
if [[ -z "$ELASTICSEARCH_PASSWORD" ]]; then
  read -rp "elasticsearch password: " ELASTICSEARCH_PASSWORD
fi
if [[ -z "$KIBANA_PASSWORD" ]]; then
  read -rp "kibana password: " KIBANA_PASSWORD
fi

# Port configuration
ELASTICSEARCH_HTTP_PORT="9200"
ELASTICSEARCH_TRANSPORT_PORT="9300"
KIBANA_PORT="5601"

# Calculate memory for Elasticsearch based on Java recommendations
TOTAL_MEMORY_MB=$(free -m | awk 'NR==2{printf "%.0f", $2}')
ES_MEMORY_MB=$((TOTAL_MEMORY_MB * 50 / 100))
if [ $ES_MEMORY_MB -lt 512 ]; then
    ES_MEMORY_MB=512
elif [ $ES_MEMORY_MB -gt 32768 ]; then
    ES_MEMORY_MB=32768
fi

ES_JAVA_OPTS="-Xms${ES_MEMORY_MB}m -Xmx${ES_MEMORY_MB}m"

echo "Total system memory: ${TOTAL_MEMORY_MB}MB"
echo "Memory allocated to Elasticsearch: ${ES_MEMORY_MB}MB"

# Install dependencies and Docker Engine + official Compose plugin
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install --yes ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key
sudo mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  echo "Downloading Docker GPG key..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
else
  echo "The Docker GPG key already exists, it will not be downloaded again."
fi

# Set up the Docker repository for Ubuntu Jammy
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index and install Docker Engine and Compose plugin
sudo apt-get update
sudo apt-get install --yes docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Ensure current user can use Docker without sudo
sudo usermod -aG docker "$(whoami)"
sudo systemctl enable --now docker

# Create installation directory
INSTALL_DIR="$HOME/kibana-stack"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create docker-compose.yaml with remote access enabled
cat > docker-compose.yaml << EOF
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=${ELASTICSEARCH_PASSWORD}
      - "ES_JAVA_OPTS=${ES_JAVA_OPTS}"
      - network.host=0.0.0.0
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
    ports:
      - "${ELASTICSEARCH_HTTP_PORT}:9200"
      - "${ELASTICSEARCH_TRANSPORT_PORT}:9300"
    networks:
      - elastic

  kibana:
    image: docker.elastic.co/kibana/kibana:${VERSION}
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD}
      - SERVER_HOST=0.0.0.0
    ports:
      - "${KIBANA_PORT}:5601"
    depends_on:
      - elasticsearch
    networks:
      - elastic

volumes:
  elasticsearch-data:
    driver: local

networks:
  elastic:
    driver: bridge
EOF

echo "docker-compose.yaml file created at $INSTALL_DIR"

# Start Elasticsearch
echo "Starting Elasticsearch..."
sudo docker compose up -d elasticsearch

# Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to respond..."
until sudo curl -s -u elastic:${ELASTICSEARCH_PASSWORD} http://localhost:${ELASTICSEARCH_HTTP_PORT} >/dev/null; do
    echo "Waiting for Elasticsearch to start..."
    sleep 5
done

echo "Elasticsearch is ready"

# Set password for kibana_system
echo "Setting password for kibana_system..."
sudo docker compose exec -T elasticsearch \
  curl -X POST -u elastic:${ELASTICSEARCH_PASSWORD} \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}" \
  http://localhost:9200/_security/user/kibana_system/_password

# Start Kibana
echo "Starting Kibana..."
sudo docker compose up -d kibana

# Wait for Kibana to be ready
KIBANA_RETRIES=0
while [ $KIBANA_RETRIES -lt 15 ]; do
    if curl -s http://localhost:${KIBANA_PORT} >/dev/null; then
        echo "✅ Kibana is up and running!"
        break
    else
        echo "Waiting for Kibana to be ready... (attempt $((KIBANA_RETRIES + 1))/15)"
        sleep 10
        KIBANA_RETRIES=$((KIBANA_RETRIES + 1))
    fi
done

if [ $KIBANA_RETRIES -eq 15 ]; then
    echo "⚠️ Kibana did not respond after several attempts. Check logs:"
    sudo docker compose logs --tail=50 kibana
fi

# Create systemd service
SERVICE_NAME="docker-compose-kibana"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Creating systemd service..."
sudo bash -c "cat > ${SERVICE_FILE}" << EOF
[Unit]
Description=Docker Compose Kibana Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl start ${SERVICE_NAME}

echo ""
echo "=== SUMMARY ==="
echo "  - Elasticsearch: http://<YOUR_VM_IP>:${ELASTICSEARCH_HTTP_PORT}"
echo "  - Kibana:        http://<YOUR_VM_IP>:${KIBANA_PORT}"
echo ""
echo "Credentials:"
echo "  - elastic / ${ELASTICSEARCH_PASSWORD}"
echo "  - kibana_system / ${KIBANA_PASSWORD}"
echo ""
echo "The service '${SERVICE_NAME}' will automatically start on system boot."