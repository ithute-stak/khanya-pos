#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-compose.images.yaml}"
ENV_FILE="${ENV_FILE:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.production.example to .env and set production secrets first." >&2
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Missing $COMPOSE_FILE." >&2
  exit 1
fi

# Read values without sourcing Docker's env file as shell code. This keeps
# spaces and other valid Compose env-file values from being executed by bash.
env_value() {
  local key="$1"
  local fallback="$2"
  local value

  value="$(sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r')"
  if [[ -z "$value" ]]; then
    printf '%s' "$fallback"
    return
  fi

  if [[ ( "$value" == \"*\" && "$value" == *\" ) || ( "$value" == \'*\' && "$value" == *\' ) ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "$value"
}

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(env_value COMPOSE_PROJECT_NAME khanya-pos)}"
POSTGRES_USER="${POSTGRES_USER:-$(env_value POSTGRES_USER khanya)}"
POSTGRES_DB="${POSTGRES_DB:-$(env_value POSTGRES_DB khanya)}"
KHANYA_API_HOST_PORT="${KHANYA_API_HOST_PORT:-$(env_value KHANYA_API_HOST_PORT 18009)}"
KHANYA_IMAGE_TAG="${KHANYA_IMAGE_TAG:-$(env_value KHANYA_IMAGE_TAG latest)}"

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

if ! docker network inspect public-edge >/dev/null 2>&1; then
  echo "Required Docker network 'public-edge' does not exist." >&2
  echo "The shared VPS Caddy edge must provide this network before Khanya is deployed." >&2
  exit 1
fi

echo "==> Pulling published Khanya API image and infrastructure images"
compose pull api outbox-worker db redis minio

echo "==> Ensuring PostgreSQL, Redis and MinIO are running"
compose up -d db redis minio

echo "==> Waiting for PostgreSQL readiness"
for _ in $(seq 1 60); do
  if compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null

echo "==> Applying Alembic migrations using the pulled API image"
compose run --rm --no-deps api alembic upgrade head

echo "==> Starting Khanya API and outbox worker"
compose up -d --remove-orphans api outbox-worker

echo "==> Current services"
compose ps

echo "==> Waiting for API liveness on 127.0.0.1:${KHANYA_API_HOST_PORT}"
for _ in $(seq 1 60); do
  if curl --fail --silent "http://127.0.0.1:${KHANYA_API_HOST_PORT}/api/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl --fail --silent "http://127.0.0.1:${KHANYA_API_HOST_PORT}/api/v1/health" >/dev/null

echo "==> Waiting for API readiness"
curl --fail --silent "http://127.0.0.1:${KHANYA_API_HOST_PORT}/api/v1/health/ready" >/dev/null

echo "Deployment complete."
echo "Image tag: ${KHANYA_IMAGE_TAG}"
echo "Local API: http://127.0.0.1:${KHANYA_API_HOST_PORT}"
echo "Caddy upstream: khanya-api:8009 on public-edge"
echo "Public API: https://api.khanya.ithute.co.ls"
