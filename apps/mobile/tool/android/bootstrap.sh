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
camera_permission = '<uses-permission android:name="android.permission.CAMERA"/>'

if permission not in text:
    marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    if marker not in text:
        raise SystemExit("Could not locate the Android <manifest> declaration")
    text = text.replace(marker, f"{marker}\n    {permission}", 1)

if camera_permission not in text:
    marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    text = text.replace(marker, f"{marker}\n    {camera_permission}", 1)

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

# Older Samsung/Android GPUs can show stale text glyphs with Impeller.
# Disable it in the generated runner so text fields render reliably.
impeller_meta = (
    '        <meta-data\n'
    '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
    '            android:value="false" />\n'
)
if 'io.flutter.embedding.android.EnableImpeller' not in text:
    marker = '    </application>'
    if marker not in text:
        raise SystemExit("Could not locate Android </application>")
    text = text.replace(marker, impeller_meta + marker, 1)

manifest.write_text(text, encoding="utf-8")

rendered = manifest.read_text(encoding="utf-8")
if permission not in rendered:
    raise SystemExit("INTERNET permission is missing from the release manifest")
if camera_permission not in rendered:
    raise SystemExit("CAMERA permission is missing from the release manifest")
if 'android:label="Khanya"' not in rendered:
    raise SystemExit("Android application label was not set to Khanya")
if 'io.flutter.embedding.android.EnableImpeller' not in rendered:
    raise SystemExit("Impeller opt-out was not applied")
PY

echo "==> Applying Khanya launcher icon"
dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import re
import sys

manifest = Path(sys.argv[1])
text = manifest.read_text(encoding="utf-8")
text, icon_count = re.subn(
    r'android:icon="@mipmap/[^"]+"',
    'android:icon="@mipmap/khanya_launcher"',
    text,
    count=1,
)
if icon_count != 1:
    raise SystemExit("Could not bind Android icon to Khanya launcher resource")

if 'android:roundIcon=' in text:
    text = re.sub(
        r'android:roundIcon="@mipmap/[^"]+"',
        'android:roundIcon="@mipmap/khanya_launcher"',
        text,
        count=1,
    )

manifest.write_text(text, encoding="utf-8")

expected = [
    Path("android/app/src/main/res/mipmap-mdpi/khanya_launcher.png"),
    Path("android/app/src/main/res/mipmap-hdpi/khanya_launcher.png"),
    Path("android/app/src/main/res/mipmap-xhdpi/khanya_launcher.png"),
]
missing = [str(path) for path in expected if not path.exists()]
if missing:
    raise SystemExit(f"Khanya launcher resources were not generated: {missing}")
PY

echo "==> Applying Khanya POS native splash branding"
dart run flutter_native_splash:create

echo "Android app name, release networking, Khanya launcher icon, and splash branding are configured."
