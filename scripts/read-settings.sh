#!/bin/bash
set -euo pipefail
# Reads plugin settings from .claude/jar-explorer.local.md
# Usage: source read-settings.sh; PROVIDER=$(read_provider)

read_provider() {
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local settings_file="$plugin_root/.claude/jar-explorer.local.md"
  local provider="native"
  if [[ -f "$settings_file" ]]; then
    provider=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$settings_file" \
      | grep '^provider:' | sed 's/provider: *//' | tr -d '[:space:]')
  fi
  echo "${provider:-native}"
}
