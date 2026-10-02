#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${KHANYA_APP_DIR:-/opt/khanya-pos}"
REPO="ithute-stak/khanya-pos"
API="https://api.github.com/repos/$REPO"
HELPER="$APP_DIR/scripts/deploy-production-manual.sh"

test -x "$HELPER" || {
  echo "Missing executable deployment helper: $HELPER" >&2
  exit 1
}

tmpdir="$(mktemp -d /tmp/khanya-latest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[Khanya] Resolving current main SHA"
curl --retry 5 --retry-delay 2 --retry-all-errors -fsSL   "$API/branches/main" -o "$tmpdir/main.json"

MAIN_SHA="$(python3 - "$tmpdir/main.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
sha = data.get("commit", {}).get("sha", "")
if len(sha) != 40 or any(ch not in "0123456789abcdef" for ch in sha):
    raise SystemExit("GitHub did not return a valid main SHA")
print(sha)
PY
)"

echo "[Khanya] Current main: $MAIN_SHA"

echo "[Khanya] Checking release-image publication for current main"
curl --retry 5 --retry-delay 2 --retry-all-errors -fsSL   "$API/actions/workflows/release-images.yml/runs?branch=main&per_page=50"   -o "$tmpdir/releases.json"

python3 - "$MAIN_SHA" "$tmpdir/releases.json" <<'PY'
import json, sys
sha, path = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    runs = json.load(handle).get("workflow_runs", [])
matches = [
    run for run in runs
    if run.get("head_sha") == sha
    and run.get("head_branch") == "main"
    and run.get("status") == "completed"
    and run.get("conclusion") == "success"
]
if not matches:
    raise SystemExit(
        f"[Khanya] Refusing deployment: no successful Khanya Release Images run for current main {sha}"
    )
print("[Khanya] Tested GHCR image is published and approved.")
PY

if [ "$(id -u)" -eq 0 ]; then
  exec "$HELPER" "$MAIN_SHA"
else
  exec sudo "$HELPER" "$MAIN_SHA"
fi
