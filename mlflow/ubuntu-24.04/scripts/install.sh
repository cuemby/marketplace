#!/bin/bash

set -e

echo "[INFO] Verifying Docker..."
if ! command -v docker &> /dev/null; then
    echo "[INFO] Docker not found. Installing Docker..."
    apt-get update
    apt-get install -y docker.io
    systemctl enable --now docker
else
    echo "[INFO] Docker is already install."
fi

echo "[INFO] Verifying Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "[INFO] Installig Docker Compose..."
    apt-get install -y docker-compose
else
    echo "[INFO] Docker Compose is already install."
fi

echo "[INFO] Creating directories for MLflow..."
mkdir -p /opt/mlflow/artifacts
mkdir -p /opt/mlflow/db

echo "[INFO] Creating file docker-compose.yml..."
cat > /opt/mlflow/docker-compose.yml <<'EOF'
version: '3.7'
services:
  mlflow:
    image: ghcr.io/mlflow/mlflow:latest
    container_name: mlflow
    ports:
      - "5000:5000"
    volumes:
      - ./artifacts:/mlflow/artifacts
      - ./db:/mlflow/db
    environment:
      - MLFLOW_BACKEND_STORE_URI=sqlite:///mlflow.db
      - MLFLOW_DEFAULT_ARTIFACT_ROOT=/mlflow/artifacts
    command: >
      mlflow server
        --backend-store-uri sqlite:///mlflow.db
        --default-artifact-root /mlflow/artifacts
        --host 0.0.0.0
EOF

echo "[INFO] Starting MLflow..."
cd /opt/mlflow
docker-compose up -d

echo "[INFO] MLflow is already running. You can access it with: http://<tu-ip-servidor>:5000"