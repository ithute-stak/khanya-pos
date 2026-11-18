#!/usr/bin/env bash
# Safe all-image pull: sudo bash pull-khanya-latest.sh
# Pulls only: no Compose up, migration, DB recreation, or release cutover.
set -Eeuo pipefail
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
[[ $# -eq 0 || "$1" == "--pull-only" ]] || { echo "Only --pull-only is supported until production cutover is approved" >&2; exit 2; }
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
echo "[Khanya] Running containers, release, and persistent data are unchanged."
echo "[Khanya] Release available locally: $sha"
echo "[Khanya] API image: $api_image"
echo "[Khanya] Web image: $web_image"
echo "[Khanya] Worker uses the same API image."
echo "[Khanya] Database, Redis, and MinIO images pulled, NOT restarted."
