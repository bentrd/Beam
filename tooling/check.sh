#!/bin/zsh
# Repeatable acceptance checks; no account, API calls or live feeds required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build
BIN_DIR="$(swift build --show-bin-path)"
for check in check-jev check-store check-feeds check-extract; do
  "$BIN_DIR/$check" --offline
done
"$BIN_DIR/beam-eval" all --offline
"$BIN_DIR/Beam" -selfcheck YES
