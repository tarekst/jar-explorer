#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS_FILE="$PLUGIN_ROOT/.claude/jar-explorer.local.md"
PROVIDER="${1:?Usage: set-provider.sh <native|vineflower>}"

if [[ "$PROVIDER" != "native" && "$PROVIDER" != "vineflower" ]]; then
  echo "ERROR: Invalid provider '$PROVIDER'. Use 'native' or 'vineflower'." >&2
  exit 1
fi

mkdir -p "$PLUGIN_ROOT/.claude"

cat > "$SETTINGS_FILE" << EOF
---
provider: $PROVIDER
---
EOF

echo "Provider set to: $PROVIDER"

# If vineflower, ensure vineflower.jar is available
if [[ "$PROVIDER" == "vineflower" ]]; then
  bash "$PLUGIN_ROOT/scripts/setup-vineflower.sh"
fi
