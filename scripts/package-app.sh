#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Packaging requires macOS (ditto, lipo and codesign).' >&2
  exit 1
fi
if [[ "$#" -gt 2 ]]; then
  echo 'Usage: package-app.sh [build-directory] [package-label]' >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/dist}"
OUTPUT="$(cd "$OUTPUT" && pwd)"
LABEL="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")}"
if [[ ! "$LABEL" =~ ^[[:alnum:]][[:alnum:]._-]*$ ]]; then
  echo 'Package labels may contain only letters, digits, dots, underscores and hyphens.' >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PACKAGE="Codex Meter $LABEL"
ARCHIVE="Codex-Meter-$LABEL.zip"
mkdir "$STAGE/$PACKAGE"
ditto --norsrc --noextattr --noqtn --noacl \
  "$OUTPUT/Codex Meter.app" "$STAGE/$PACKAGE/Codex Meter.app"
cp "$OUTPUT/codex-meter" "$STAGE/$PACKAGE/codex-meter"
cp "$ROOT/Resources/INSTALL.txt" "$STAGE/$PACKAGE/INSTALL.txt"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "$STAGE/$PACKAGE" "$STAGE/$ARCHIVE"

# Verify the extracted files users will install before exporting the archive.
mkdir "$STAGE/check"
unzip -q "$STAGE/$ARCHIVE" -d "$STAGE/check"
CHECK_ROOT="$STAGE/check/$PACKAGE"
CHECK_APP="$CHECK_ROOT/Codex Meter.app"
/usr/bin/plutil -lint "$CHECK_APP/Contents/Info.plist"
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$CHECK_APP/Contents/Info.plist")"
if [[ "$ICON_NAME" != 'AppIcon' || ! -s "$CHECK_APP/Contents/Resources/AppIcon.icns" ]]; then
  echo 'The extracted app must reference and include AppIcon.icns.' >&2
  exit 1
fi
/usr/bin/iconutil --convert iconset --output "$STAGE/check-icon.iconset" \
  "$CHECK_APP/Contents/Resources/AppIcon.icns"
if [[ ! -s "$STAGE/check-icon.iconset/icon_512x512@2x.png" ]]; then
  echo 'The extracted app icon is missing its 1024-pixel Retina image.' >&2
  exit 1
fi
for LOCALIZATION in en zh-Hans; do
  /usr/bin/plutil -lint "$CHECK_APP/Contents/Resources/$LOCALIZATION.lproj/InfoPlist.strings"
done
lipo "$CHECK_ROOT/Codex Meter.app/Contents/MacOS/CodexMeter" -verify_arch arm64 x86_64
lipo "$CHECK_ROOT/codex-meter" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$CHECK_ROOT/Codex Meter.app"
codesign --verify --strict "$CHECK_ROOT/codex-meter"
"$CHECK_ROOT/codex-meter" --help >/dev/null
"$CHECK_ROOT/codex-meter" history --days 1 --json >/dev/null

(
  cd "$STAGE"
  shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
  shasum -a 256 -c "$ARCHIVE.sha256"
)
cp "$STAGE/$ARCHIVE" "$STAGE/$ARCHIVE.sha256" "$OUTPUT/"
printf 'Package: %s/%s\nChecksum: %s/%s.sha256\n' "$OUTPUT" "$ARCHIVE" "$OUTPUT" "$ARCHIVE"
