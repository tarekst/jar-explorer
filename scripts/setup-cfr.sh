#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CFR_JAR="$PLUGIN_ROOT/tools/cfr.jar"
CFR_VERSION="0.152"
CFR_URL="https://github.com/leibnitz27/cfr/releases/download/$CFR_VERSION/cfr-$CFR_VERSION.jar"

if [[ -f "$CFR_JAR" ]]; then
  exit 0
fi

mkdir -p "$PLUGIN_ROOT/tools"
echo "Downloading CFR decompiler v$CFR_VERSION..." >&2
curl -fsSL -o "$CFR_JAR" "$CFR_URL"

# Verify
if ! java -jar "$CFR_JAR" --version >/dev/null 2>&1; then
  rm -f "$CFR_JAR"
  echo "ERROR: CFR download failed or is corrupt." >&2
  exit 1
fi

echo "CFR decompiler ready." >&2
