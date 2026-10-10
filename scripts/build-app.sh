#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Building the app requires macOS (sips, iconutil, lipo and codesign).' >&2
  exit 1
fi

ROOT="${0:A:h:h}"
OUTPUT="${1:-$ROOT/dist}"
FINAL_APP="$OUTPUT/Codex Meter.app"
FINAL_CLI="$OUTPUT/codex-meter"
ICON_SOURCE="$ROOT/Resources/AppIcon.png"
STAGE="$(mktemp -d)"
APP="$STAGE/Codex Meter.app"
ICONSET="$STAGE/AppIcon.iconset"
trap 'rm -rf "$STAGE"' EXIT

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon: $ICON_SOURCE" >&2
  exit 1
fi
/usr/bin/sips -g pixelWidth -g pixelHeight -g format "$ICON_SOURCE" | /usr/bin/awk '
  $1 == "pixelWidth:" { width = $2 }
  $1 == "pixelHeight:" { height = $2 }
  $1 == "format:" { format = $2 }
  END { exit !(width == 1024 && height == 1024 && format == "png") }
' || {
  echo 'Resources/AppIcon.png must be a 1024 x 1024 PNG.' >&2
  exit 1
}
/usr/bin/plutil -lint "$ROOT/Resources/Info.plist"

cd "$ROOT"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ROOT/.build-arm64"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$ROOT/.build-x86_64"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create \
  "$ROOT/.build-arm64/arm64-apple-macosx/release/CodexMeter" \
  "$ROOT/.build-x86_64/x86_64-apple-macosx/release/CodexMeter" \
  -output "$APP/Contents/MacOS/CodexMeter"
xcrun lipo -create \
  "$ROOT/.build-arm64/arm64-apple-macosx/release/codex-meter" \
  "$ROOT/.build-x86_64/x86_64-apple-macosx/release/codex-meter" \
  -output "$STAGE/codex-meter"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# macOS uses ICNS; create every standard and Retina size with system tools.
mkdir "$ICONSET"
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$ICON_SOURCE" \
    --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  RETINA_SIZE=$((SIZE * 2))
  /usr/bin/sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$ICON_SOURCE" \
    --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

# Bundle metadata translations are resolved by macOS from these directories.
for LOCALIZATION in "$ROOT"/Resources/*.lproj(N); do
  cp -R "$LOCALIZATION" "$APP/Contents/Resources/"
done

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
codesign --force --sign - "$STAGE/codex-meter"

rm -rf "$FINAL_APP"
mkdir -p "$OUTPUT"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$FINAL_APP"
xattr -cr "$FINAL_APP"
codesign --force --deep --sign - "$FINAL_APP"
codesign --verify --deep --strict "$FINAL_APP"
cp "$STAGE/codex-meter" "$FINAL_CLI"
chmod 755 "$FINAL_CLI"
codesign --verify --strict "$FINAL_CLI"
echo "$FINAL_APP"
