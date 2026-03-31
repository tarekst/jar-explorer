#!/bin/bash
set -euo pipefail

# Usage: list-jar.sh <jar-path> [filter-pattern]
# Lists classes in a JAR, optionally filtered by pattern.
# Output: one FQCN per line, sorted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/resolve-java.sh"

JAR_PATH="${1:?Usage: list-jar.sh <jar-path> [filter-pattern]}"
FILTER="${2:-}"

if [[ ! -f "$JAR_PATH" ]]; then
  echo "ERROR: JAR not found: $JAR_PATH" >&2
  exit 1
fi

JAR_CMD=$(resolve_jdk_tool jar)

# List .class files, exclude module-info and inner classes by default
CLASSES=$("$JAR_CMD" tf "$JAR_PATH" 2>/dev/null \
  | grep '\.class$' \
  | grep -v 'module-info' \
  | grep -v '\$' \
  | sed 's|/|.|g; s|\.class$||')

if [[ -n "$FILTER" ]]; then
  CLASSES=$(echo "$CLASSES" | grep -i "$FILTER" || true)
fi

if [[ -z "$CLASSES" ]]; then
  echo "No classes found matching '${FILTER:-*}'" >&2
  exit 0
fi

echo "$CLASSES" | sort
