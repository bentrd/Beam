#!/bin/zsh
# Build Beam and assemble it into a signed .app.
#
# There is no Xcode on this machine, so nothing here comes from a build system: the binary comes from SwiftPM,
# the icon from tooling/make-icon.swift, and the bundle is put together by hand. The one subtlety is SwiftPM's
# resource bundles — they sit next to the binary in .build, and `Bundle.module` looks for them in
# Contents/Resources once the executable is inside an app, so they have to be copied.
#
# usage: tooling/make-app.sh [debug|release] [native|universal|arm64|x86_64]
set -euo pipefail

CONFIG="${1:-release}"
ARCH="${2:-native}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "$CONFIG" in debug|release) ;; *) echo "Configuration must be debug or release" >&2; exit 2 ;; esac
typeset -a ARCH_FLAGS
case "$ARCH" in
  native) ARCH_FLAGS=() ;;
  universal) ARCH_FLAGS=() ;;
  arm64|x86_64) ARCH_FLAGS=(--triple "$ARCH-apple-macosx26.0") ;;
  *) echo "Architecture must be native, universal, arm64 or x86_64" >&2; exit 2 ;;
esac
VERSION="$(tr -d '\n' < "$ROOT/VERSION")"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "VERSION must contain a numeric release version" >&2; exit 2; }

NAME="Beam"
BUNDLE_ID="dev.beam.app"
APP="$ROOT/build/$NAME.app"

echo "building ($CONFIG, $ARCH)…"
if [[ "$ARCH" == universal ]]; then
  # SwiftPM's multi-arch mode requires Xcode's xcbuild. Build each slice with Command Line Tools instead.
  swift build -c "$CONFIG" --triple arm64-apple-macosx26.0 --product Beam
  BIN_DIR="$(swift build -c "$CONFIG" --triple arm64-apple-macosx26.0 --show-bin-path)"
  swift build -c "$CONFIG" --triple x86_64-apple-macosx26.0 --product Beam
  INTEL_BIN_DIR="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx26.0 --show-bin-path)"
else
  swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product Beam
  BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
fi
[[ -x "$BIN_DIR/Beam" ]] || { echo "build failed: $BIN_DIR/Beam is missing" >&2; exit 1; }

if [[ ! -f "$ROOT/tooling/AppIcon.icns" ]]; then
  echo "drawing the icon…"
  swift "$ROOT/tooling/make-icon.swift" "$ROOT/tooling" >/dev/null
fi

echo "assembling…"
mkdir -p "$ROOT/build"
STAGING="$(mktemp -d "$ROOT/build/.Beam.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/$NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
if [[ "$ARCH" == universal ]]; then
  lipo -create "$BIN_DIR/Beam" "$INTEL_BIN_DIR/Beam" -output "$BUNDLE/Contents/MacOS/Beam"
  lipo "$BUNDLE/Contents/MacOS/Beam" -verify_arch arm64 x86_64
else
  cp "$BIN_DIR/Beam" "$BUNDLE/Contents/MacOS/Beam"
fi
cp "$ROOT/tooling/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

# Only the app's resources belong in the release, not acceptance-test fixtures.
[[ -d "$BIN_DIR/Beam_BeamUI.bundle" ]] || { echo "BeamUI resources are missing" >&2; exit 1; }
cp -R "$BIN_DIR/Beam_BeamUI.bundle" "$BUNDLE/Contents/Resources/"

BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>Beam</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
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
plutil -lint "$BUNDLE/Contents/Info.plist"
# Finder metadata inherited from source assets is forbidden inside a signed bundle.
xattr -cr "$BUNDLE"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

# Publish the bundle only after the build, resources and signature pass.
rm -rf "$APP"
mv "$BUNDLE" "$APP"

echo "built $APP"
