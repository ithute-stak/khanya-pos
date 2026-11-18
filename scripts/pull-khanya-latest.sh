#!/usr/bin/env bash
# Safe all-image pull: sudo bash pull-khanya-latest.sh
# Pulls only: no Compose up, migration, DB recreation, or release cutover.
set -Eeuo pipefail
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
mode="${1:---pull-only}"
[[ $# -le 1 && ( "$mode" == "--pull-only" || "$mode" == "--deploy" ) ]] || { echo "Usage: $0 [--pull-only|--deploy]" >&2; exit 2; }
exec 9>/opt/khanya-pos/releases/khanya-image-pull.lock
flock -n 9 || { echo "[Khanya] Another pull is running" >&2; exit 1; }
repo="ithute-stak/khanya-pos"
api="https://api.github.com/repos/$repo"
api_dir="/home/administrator/khanya-pos"
web_dir="/opt/khanya-pos"
for path in "$api_dir/compose.images.yaml" "$api_dir/.env" "$web_dir/web.compose.yaml" "$web_dir/web.env"; do
  test -f "$path" || { echo "[Khanya] Required deployment file missing: $path" >&2; exit 1; }
done
assert_owner() {
  local actual_project actual_file
  actual_project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$1")"
  actual_file="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$1")"
  [[ "$actual_project" == "$2" && "$actual_file" == "$3" ]] || {
    echo "[Khanya] Refusing: wrong Compose project or configuration for $1" >&2; exit 1;
  }
}
assert_owner khanya-pos-api-1 khanya-pos "$api_dir/compose.images.yaml"
assert_owner khanya-pos-outbox-worker-1 khanya-pos "$api_dir/compose.images.yaml"
assert_owner khanya-pos-db-1 khanya-pos "$api_dir/compose.images.yaml"
assert_owner khanya-web-web-1 khanya-web "$web_dir/web.compose.yaml"

tmp="$(mktemp -d /tmp/khanya-pull.XXXXXXXX)"
trap 'rm -rf "$tmp"' EXIT
curl --retry 3 --retry-all-errors -fsSL "$api/branches/main" > "$tmp/main.json"
curl --retry 3 --retry-all-errors -fsSL "$api/actions/workflows/release-images.yml/runs?branch=main&per_page=50" > "$tmp/runs.json"
sha="$(python3 - "$tmp/main.json" "$tmp/runs.json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as fh: main = json.load(fh)["commit"]["sha"]
with open(sys.argv[2]) as fh: runs = json.load(fh).get("workflow_runs", [])
assert re.fullmatch(r"[0-9a-f]{40}", main)
if not any(r.get("head_sha") == main and r.get("head_branch") == "main"
           and r.get("status") == "completed" and r.get("conclusion") == "success"
           for r in runs):
    raise SystemExit("[Khanya] Current main has no successful image-release workflow. No images pulled.")
print(main)
PY
)"
api_image="ghcr.io/ithute-stak/khanya-pos-api:$sha"
web_image="ghcr.io/ithute-stak/khanya-pos-web:$sha"
echo "[Khanya] Verifying both exact release images: $sha"
docker manifest inspect "$api_image" >/dev/null
docker manifest inspect "$web_image" >/dev/null
echo "[Khanya] Pulling Web, API, and worker image"
docker pull "$web_image"
docker pull "$api_image"
echo "[Khanya] Pulling current infrastructure images without replacing containers"
docker pull postgres:17-alpine
docker pull redis:8-alpine
docker pull quay.io/minio/aistor/minio:latest
echo "[Khanya] Pull stage complete."
echo "[Khanya] Release available locally: $sha"
echo "[Khanya] API image: $api_image"
echo "[Khanya] Web image: $web_image"
echo "[Khanya] Worker uses the same API image."
echo "[Khanya] Database, Redis, and MinIO images pulled, NOT restarted."
if [[ "$mode" == "--pull-only" ]]; then
  echo "[Khanya] All running containers and persistent data remain unchanged."
  exit 0
fi


# --deploy only modifies the verified API and Web projects; NEVER "down" or "rm".
old_api="$(docker inspect -f '{{.Config.Image}}' khanya-pos-api-1)"
old_web="$(docker inspect -f '{{.Config.Image}}' khanya-web-web-1)"
old_api_sha="\${old_api##*:}"
old_web_sha="\${old_web##*:}"
[[ "$old_api_sha" =~ ^[0-9a-f]{40}$ && "$old_web_sha" =~ ^[0-9a-f]{40}$ ]] || {
  echo "[Khanya] Running images lack immutable 40-character tags; refusing cutover." >&2; exit 1
}
docker image inspect "$old_api" "$old_web" >/dev/null
if grep -Eiq '^[[:space:]]*PURCHASE_ORDER_RECEIPT_V2_ENABLED[[:space:]]*=[[:space:]]*(1|true|yes)' "$api_dir/.env"; then
  echo "[Khanya] Unfinished goods-receiving gate enabled; refusing deployment." >&2; exit 1
fi
export KHANYA_IMAGE_TAG="$sha" KHANYA_WEB_IMAGE_TAG="$sha" KHANYA_ENV_FILE="$api_dir/.env"
api_compose=(docker compose -p khanya-pos --env-file "$api_dir/.env" -f "$api_dir/compose.images.yaml")
web_compose=(docker compose -p khanya-web --env-file "$web_dir/web.env" -f "$web_dir/web.compose.yaml")
"\${api_compose[@]}" config --quiet
"\${web_compose[@]}" config --quiet
echo "[Khanya] Checking candidate backend imports"
docker run --rm --entrypoint python "$api_image" -c 'import app.main; import alembic' >/dev/null
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="/opt/khanya-pos/backups/khanya-before-\${sha}-\${timestamp}.dump"
echo "[Khanya] Backing up the ACTUAL khanya-pos DB container"
docker exec khanya-pos-db-1 sh -c 'exec pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup"
test -s "$backup"
docker exec -i khanya-pos-db-1 pg_restore --list < "$backup" >/dev/null
chmod 600 "$backup"
echo "[Khanya] Verified backup: $backup"

cutover=0
rollback_apps() {
  if (( cutover == 1 )); then
    echo "[Khanya] Failure: restoring previous application images (NOT reverting DB migrations)" >&2
    export KHANYA_IMAGE_TAG="$old_api_sha" KHANYA_WEB_IMAGE_TAG="$old_web_sha"
    "\${api_compose[@]}" up -d --no-deps --pull never api outbox-worker || true
    "\${web_compose[@]}" up -d --no-deps --pull never web || true
    echo "[Khanya] Manual DB recovery backup: $backup" >&2
  fi
}
trap 'rollback_apps; rm -rf "$tmp"' ERR
echo "[Khanya] Running Alembic migration from tested image"
"\${api_compose[@]}" run --rm --no-deps --entrypoint alembic api upgrade head
cutover=1
echo "[Khanya] Replacing API without touching persistent containers"
"\${api_compose[@]}" up -d --no-deps --pull never api
healthy() {
  local container="$1" n state
  for n in $(seq 1 40); do
    state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
    [[ "$state" == healthy ]] && return 0
    [[ "$state" == unhealthy || "$state" == exited ]] && return 1
    sleep 3
  done
  return 1
}
healthy khanya-pos-api-1
"\${api_compose[@]}" up -d --no-deps --pull never outbox-worker
[[ "$(docker inspect -f '{{.State.Running}}' khanya-pos-outbox-worker-1)" == true ]]
echo "[Khanya] Replacing Web in separate khanya-web project"
"\${web_compose[@]}" up -d --no-deps --pull never web
healthy khanya-web-web-1
curl --retry 5 --retry-delay 2 -fsS --max-time 15 https://api.khanya.ithute.co.ls/api/v1/health >/dev/null
curl --retry 5 --retry-delay 2 -fsS --max-time 15 https://pos.ithute.co.ls/ >/dev/null
printf '%s\n' "$sha" > /opt/khanya-pos/releases/current.sha
printf '%s\n' "$old_api_sha" > /opt/khanya-pos/releases/previous-api.sha
printf '%s\n' "$old_web_sha" > /opt/khanya-pos/releases/previous-web.sha
cutover=0
echo "[Khanya] Production healthy: $sha | Backup: $backup"
