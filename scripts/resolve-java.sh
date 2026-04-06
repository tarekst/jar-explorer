#!/bin/bash
set -euo pipefail
# Resolves the path to a JDK tool (jar, javap, etc.)
# Usage: source resolve-java.sh; then use $JAR_CMD
# On Windows/Git Bash, 'jar' may not be on PATH even if 'java' is.

resolve_jdk_tool() {
  local tool="${1:-jar}"

  # Already on PATH?
  if command -v "$tool" &>/dev/null; then
    echo "$tool"
    return 0
  fi

  # Resolve from java.home property
  local java_home
  java_home=$(java -XshowSettings:properties 2>&1 \
    | grep 'java.home' \
    | sed 's/.*= //' \
    | sed 's|\\|/|g' \
    | sed 's|^\([A-Za-z]\):|/\L\1|')

  if [[ -z "$java_home" ]]; then
    echo "ERROR: Cannot determine JAVA_HOME" >&2
    return 1
  fi

  # Try java.home/bin/tool first, then parent/bin/tool (JRE vs JDK)
  local candidate="$java_home/bin/$tool"
  if [[ -f "$candidate" || -f "${candidate}.exe" ]]; then
    echo "$candidate"
    return 0
  fi

  candidate="$(dirname "$java_home")/bin/$tool"
  if [[ -f "$candidate" || -f "${candidate}.exe" ]]; then
    echo "$candidate"
    return 0
  fi

  echo "ERROR: '$tool' not found in JDK at $java_home" >&2
  return 1
}
