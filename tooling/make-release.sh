#!/bin/zsh
# Build a verified universal macOS app, archive it and publish its checksum locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ARCH="${1:-universal}"
"$ROOT/tooling/make-app.sh" release "$ARCH"
"$ROOT/build/Beam.app/Contents/MacOS/Beam" -selfcheck YES
xattr -cr "$ROOT/build/Beam.app"
codesign --verify --deep --strict "$ROOT/build/Beam.app"
VERSION="$(tr -d '\n' < "$ROOT/VERSION")"
ARCHIVE="Beam-$VERSION-macOS-$ARCH.zip"
# File Provider can reattach Finder metadata after assembly. Exclude it from the download entirely.
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$ROOT/build/Beam.app" "$ROOT/build/$ARCHIVE"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beam-release.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ROOT/build/$ARCHIVE" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Beam.app"
cd "$ROOT/build"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
echo "Release: $ROOT/build/$ARCHIVE"
