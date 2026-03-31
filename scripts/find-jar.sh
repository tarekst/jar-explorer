#!/bin/bash
set -euo pipefail

# Usage: find-jar.sh <jar-path-or-artifact>
# Resolves a JAR file path from:
#   - Direct file path (absolute or relative)
#   - Maven coordinate (group:artifact:version)
#   - Partial name (searches Maven, Gradle, CWD)

INPUT="${1:?Usage: find-jar.sh <jar-path-or-artifact>}"

# Direct path — absolute or relative
if [[ -f "$INPUT" ]]; then
  echo "$INPUT"
  exit 0
fi

# Maven coordinate: group:artifact:version
if [[ "$INPUT" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
  GROUP="${BASH_REMATCH[1]}"
  ARTIFACT="${BASH_REMATCH[2]}"
  VERSION="${BASH_REMATCH[3]}"
  GROUP_PATH="${GROUP//\.//}"
  M2_PATH="$HOME/.m2/repository/$GROUP_PATH/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION.jar"
  if [[ -f "$M2_PATH" ]]; then
    echo "$M2_PATH"
    exit 0
  fi
  echo "ERROR: JAR not found at $M2_PATH" >&2
  exit 1
fi

# Partial name search — use cached JAR index for speed
CACHE_BASE="${TMPDIR:-${TEMP:-/tmp}}/jar-explorer-cache"
INDEX_FILE="$CACHE_BASE/jar-index.txt"
mkdir -p "$CACHE_BASE"

# Build/refresh index (cached for 1 hour)
if [[ ! -f "$INDEX_FILE" ]] || {
  if stat --version &>/dev/null 2>&1; then
    [[ $(( $(date +%s) - $(stat -c %Y "$INDEX_FILE" 2>/dev/null || echo 0) )) -gt 3600 ]]
  else
    [[ $(( $(date +%s) - $(stat -f %m "$INDEX_FILE" 2>/dev/null || echo 0) )) -gt 3600 ]]
  fi
}; then
  SEARCH_DIRS=()
  [[ -d "$HOME/.m2/repository" ]] && SEARCH_DIRS+=("$HOME/.m2/repository")
  [[ -d "$HOME/.gradle/caches" ]] && SEARCH_DIRS+=("$HOME/.gradle/caches")
  if [[ ${#SEARCH_DIRS[@]} -gt 0 ]]; then
    find "${SEARCH_DIRS[@]}" -name "*.jar" \
      -not -name "*-sources*" -not -name "*-javadoc*" \
      -type f 2>/dev/null > "$INDEX_FILE" || true
  fi
fi

# Search index + CWD
MATCHES=()
if [[ -f "$INDEX_FILE" ]]; then
  while IFS= read -r match; do
    MATCHES+=("$match")
  done < <(grep -i "$INPUT" "$INDEX_FILE" 2>/dev/null | head -20)
fi
# Also check CWD
while IFS= read -r match; do
  MATCHES+=("$match")
done < <(find "." -maxdepth 4 -name "*${INPUT}*.jar" -type f 2>/dev/null | head -5)

if [[ ${#MATCHES[@]} -eq 0 ]]; then
  echo "ERROR: No JAR found matching '$INPUT'" >&2
  echo "Searched in: ${SEARCH_DIRS[*]}" >&2
  exit 1
fi

if [[ ${#MATCHES[@]} -eq 1 ]]; then
  echo "${MATCHES[0]}"
  exit 0
fi

# Multiple matches — list them
echo "Multiple JARs found matching '$INPUT':" >&2
for i in "${!MATCHES[@]}"; do
  echo "  [$((i+1))] ${MATCHES[$i]}" >&2
done
echo "" >&2
echo "Please specify the full path or a more specific name." >&2

# Return the first match as default
echo "${MATCHES[0]}"
