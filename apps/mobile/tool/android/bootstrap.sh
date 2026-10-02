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
import re
import sys

manifest = Path(sys.argv[1])
text = manifest.read_text(encoding="utf-8")
permission = '<uses-permission android:name="android.permission.INTERNET"/>'

if permission not in text:
    marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    if marker not in text:
        raise SystemExit("Could not locate the Android <manifest> declaration")
    text = text.replace(marker, f"{marker}\n    {permission}", 1)

# The Dart package remains khanya_pos internally, but the installed app must
# present the commercial product name to users.
text, count = re.subn(
    r'android:label="[^"]*"',
    'android:label="Khanya"',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("Could not set the Android application label to Khanya")

manifest.write_text(text, encoding="utf-8")

rendered = manifest.read_text(encoding="utf-8")
if permission not in rendered:
    raise SystemExit("INTERNET permission is missing from the release manifest")
if 'android:label="Khanya"' not in rendered:
    raise SystemExit("Android application label was not set to Khanya")
PY

echo "==> Applying Khanya launcher icon"
dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml

echo "==> Applying Khanya POS native splash branding"
dart run flutter_native_splash:create

echo "Android app name, release networking, Khanya launcher icon, and splash branding are configured."
