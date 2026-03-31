#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
VINEFLOWER_JAR="$PLUGIN_ROOT/tools/vineflower.jar"
VINEFLOWER_VERSION="1.11.0"
VINEFLOWER_URL="https://github.com/Vineflower/vineflower/releases/download/$VINEFLOWER_VERSION/vineflower-$VINEFLOWER_VERSION.jar"

if [[ -f "$VINEFLOWER_JAR" ]]; then
  exit 0
fi

mkdir -p "$PLUGIN_ROOT/tools"
echo "Downloading Vineflower decompiler v$VINEFLOWER_VERSION..." >&2
curl -fsSL -o "$VINEFLOWER_JAR" "$VINEFLOWER_URL"

# Verify
if ! java -jar "$VINEFLOWER_JAR" --version >/dev/null 2>&1; then
  rm -f "$VINEFLOWER_JAR"
  echo "ERROR: Vineflower download failed or is corrupt." >&2
  exit 1
fi

echo "Vineflower decompiler ready." >&2
