#!/usr/bin/env bash
# Build and run PostgreSQL with schema + seed for medical-mcp-toolkit
set -euo pipefail

DB_IMAGE_NAME="${DB_IMAGE_NAME:-medical-db}"
DB_CONTAINER_NAME="${DB_CONTAINER_NAME:-medical-db-container}"
DB_PORT="${DB_PORT:-5432}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required. Please install Docker and try again."
  exit 1
fi

echo "Building PostgreSQL Docker image: ${DB_IMAGE_NAME} ..."
docker build -t "${DB_IMAGE_NAME}" -f Dockerfile.db .

if [ -n "$(docker ps -aq -f status=exited -f name=${DB_CONTAINER_NAME})" ]; then
  echo "Removing stopped container ${DB_CONTAINER_NAME} ..."
  docker rm "${DB_CONTAINER_NAME}"
fi

if [ -n "$(docker ps -q -f name=${DB_CONTAINER_NAME})" ]; then
  echo "Container ${DB_CONTAINER_NAME} is already running; restarting ..."
  docker stop "${DB_CONTAINER_NAME}" || true
  docker rm "${DB_CONTAINER_NAME}" || true
fi

echo "Starting PostgreSQL container: ${DB_CONTAINER_NAME} ..."
docker run -d --name "${DB_CONTAINER_NAME}" \
  -e POSTGRES_USER=mcp_user \
  -e POSTGRES_PASSWORD=mcp_password \
  -e POSTGRES_DB=medical_db \
  -p "${DB_PORT}:5432" \
  "${DB_IMAGE_NAME}"

echo "Waiting for database to initialize ..."
sleep 10
echo "✅ Database is ready on port ${DB_PORT}"
echo "Logs: docker logs -f ${DB_CONTAINER_NAME}"
