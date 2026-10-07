#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p build
"$GODOT_BIN" --headless --editor --import --quit
rm -f build/Botball-Lab-macOS.zip
"$GODOT_BIN" --headless --export-release macOS build/Botball-Lab-macOS.zip
