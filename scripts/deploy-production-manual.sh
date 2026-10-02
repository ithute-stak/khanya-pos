#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_SHA="${1:-}"
APP_DIR="${KHANYA_APP_DIR:-/opt/khanya-pos}"
API_IMAGE="ghcr.io/ithute-stak/khanya-pos-api"

if [[ ! "$RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Usage: $0 <40-character-tested-release-sha>" >&2
  exit 2
fi

cd "$APP_DIR"
test -f .env || { echo "Missing $APP_DIR/.env" >&2; exit 1; }
test -f compose.images.yaml || { echo "Missing $APP_DIR/compose.images.yaml" >&2; exit 1; }
docker network inspect public-edge >/dev/null 2>&1 || {
  echo "Missing Docker network: public-edge" >&2
  exit 1
}

mkdir -p releases backups

current_release=""
if [ -f releases/current.sha ]; then
  current_release="$(tr -d '\r\n ' < releases/current.sha)"
fi

if [ "$current_release" = "$RELEASE_SHA" ]; then
  echo "[Khanya] Production is already on $RELEASE_SHA."
  exit 0
fi

echo "[Khanya] Verifying immutable GHCR image exists"
docker manifest inspect "$API_IMAGE:$RELEASE_SHA" >/dev/null

echo "[Khanya] Pulling tested API image only"
docker pull "$API_IMAGE:$RELEASE_SHA"

export KHANYA_IMAGE_TAG="$RELEASE_SHA"
export KHANYA_ENV_FILE=.env

compose=(docker compose --env-file .env -p khanya -f compose.images.yaml)

wait_healthy() {
  local service="$1"
  local attempts="${2:-60}"
  local delay="${3:-3}"
  local container_id state

  container_id="$("${compose[@]}" ps -q "$service")"
  test -n "$container_id" || {
    echo "[Khanya] Missing container for $service" >&2
    return 1
  }

  for _ in $(seq 1 "$attempts"); do
    state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
    [ "$state" = "healthy" ] && return 0
    sleep "$delay"
  done

  echo "[Khanya] $service failed health verification: ${state:-unknown}" >&2
  "${compose[@]}" logs --tail=200 "$service" || true
  return 1
}

echo "[Khanya] Ensuring persistent services are running"
"${compose[@]}" up -d --no-build db redis minio
wait_healthy db 45 2
wait_healthy redis 45 2

set -a
# shellcheck disable=SC1091
source .env
set +a

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$APP_DIR/backups/khanya-before-${RELEASE_SHA}-${timestamp}.dump"

echo "[Khanya] Backing up PostgreSQL before migrations"
"${compose[@]}" exec -T db pg_dump   --format=custom   --no-owner   --no-privileges   -U "${POSTGRES_USER:-khanya}"   "${POSTGRES_DB:-khanya}" > "$backup"
test -s "$backup"

echo "[Khanya] Applying migrations from the pulled image"
"${compose[@]}" run --rm --no-deps migrate

echo "[Khanya] Starting API and outbox worker from pulled image"
"${compose[@]}" up -d --no-build --pull never --no-deps api
wait_healthy api 60 3
"${compose[@]}" up -d --no-build --pull never --no-deps outbox-worker

echo "[Khanya] Verifying local API health"
curl --retry 15 --retry-delay 2 --retry-all-errors -fsS   "http://127.0.0.1:${KHANYA_API_HOST_PORT:-18009}/api/v1/health" >/dev/null

if curl -fsS --max-time 10 https://api.khanya.ithute.co.ls/api/v1/health >/dev/null 2>&1; then
  echo "[Khanya] Public API health passed"
else
  echo "[Khanya] WARNING: local API is healthy but public API health check did not pass." >&2
fi

printf '%s\n' "$RELEASE_SHA" > releases/current.sha
if [ -n "$current_release" ] && [ "$current_release" != "$RELEASE_SHA" ]; then
  printf '%s\n' "$current_release" > releases/previous.sha
fi

echo "[Khanya] Deployment complete: $RELEASE_SHA"
echo "[Khanya] No source code was pulled and no image was built on this VPS."
