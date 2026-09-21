#!/bin/zsh
# Build Beam and assemble it into a signed .app.
#
# There is no Xcode on this machine, so nothing here comes from a build system: the binary comes from SwiftPM,
# the icon from tooling/make-icon.swift, and the bundle is put together by hand. The one subtlety is SwiftPM's
# resource bundles — they sit next to the binary in .build, and `Bundle.module` looks for them in
# Contents/Resources once the executable is inside an app, so they have to be copied.
#
# usage: tooling/make-app.sh [Configuration]      (debug or release; release by default)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="Beam"
BUNDLE_ID="dev.beam.app"
APP="$ROOT/build/$NAME.app"

echo "building ($CONFIG)…"
swift build -c "$CONFIG" --product Beam 2>&1 | grep -E "error|warning: .*never used|Build complete" || true
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
[[ -x "$BIN_DIR/Beam" ]] || { echo "build failed: $BIN_DIR/Beam is missing" >&2; exit 1; }

if [[ ! -f "$ROOT/tooling/AppIcon.icns" ]]; then
  echo "drawing the icon…"
  swift "$ROOT/tooling/make-icon.swift" "$ROOT/tooling" >/dev/null
fi

echo "assembling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Beam" "$APP/Contents/MacOS/Beam"
cp "$ROOT/tooling/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (BeamUI's captured FakeData, and anything else a target declares).
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

VERSION="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>Beam</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.news</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><true/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Beam</string>
</dict></plist>
PLIST

# Ad-hoc signing, after everything is in place: signing first and copying second invalidates the signature.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
  || echo "note: ad-hoc signing failed; the app will still run locally"

# The one thing that silently breaks a hand-made bundle: a resource bundle that did not come along.
if [[ -d "$APP/Contents/Resources/Beam_BeamUI.bundle" ]]; then
  echo "resources: BeamUI bundle present"
else
  echo "WARNING: BeamUI's resource bundle is missing; -fake YES will not find its captured data" >&2
fi

echo "built $APP"
