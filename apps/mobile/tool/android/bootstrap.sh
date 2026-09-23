#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$MOBILE_DIR"

if [[ ! -d android ]]; then
  echo "Generating Android runner for Khanya POS"
  flutter create \
    --platforms=android \
    --project-name khanya_pos \
    --org ls.co.ithute \
    .
fi

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Android manifest was not generated: $MANIFEST" >&2
  exit 1
fi

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import sys

manifest = Path(sys.argv[1])
text = manifest.read_text(encoding="utf-8")
permission = '<uses-permission android:name="android.permission.INTERNET"/>'

if permission not in text:
    marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    if marker not in text:
        raise SystemExit("Could not locate the Android <manifest> declaration")
    text = text.replace(marker, f"{marker}\n    {permission}", 1)
    manifest.write_text(text, encoding="utf-8")

if permission not in manifest.read_text(encoding="utf-8"):
    raise SystemExit("INTERNET permission is missing from the release manifest")
PY

echo "Android release networking is configured."
