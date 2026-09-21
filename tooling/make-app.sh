#!/bin/zsh
# Build a SwiftPM executable and wrap it in a signed macOS .app bundle.
# usage: make-app.sh <ExecutableTarget> <Display Name> <bundle.id> [icon.icns]
set -euo pipefail

TARGET="$1"; NAME="$2"; BUNDLE_ID="$3"; ICON="${4:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product "$TARGET" 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -20 || true
BIN="$(swift build -c release --show-bin-path)/$TARGET"
[[ -x "$BIN" ]] || { echo "build failed: $BIN missing" >&2; exit 1; }

APP="$ROOT/build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$TARGET"
[[ -n "$ICON" && -f "$ICON" ]] && cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles, if any, must sit next to the executable's Resources.
for bundle in "$(dirname "$BIN")"/*.bundle(N); do cp -R "$bundle" "$APP/Contents/Resources/"; done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$TARGET</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><true/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc signing failed; app will still run locally"
echo "built $APP"
