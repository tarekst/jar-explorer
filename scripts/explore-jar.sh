#!/bin/bash
set -euo pipefail

# Usage: explore-jar.sh <jar-path> <mode> [criteria]
# Modes: class, package, search, method, source, list
#
# Fast modes (javap — instant, compact output):
#   explore-jar.sh lib.jar class com.example.MyClass      # signatures
#   explore-jar.sh lib.jar package com.example.util        # all signatures in package
#   explore-jar.sh lib.jar method com.example.Foo#bar      # find method signature
#   explore-jar.sh lib.jar search "keyword"                # search signatures, then source
#   explore-jar.sh lib.jar list [filter]                   # list classes
#
# Full decompilation (CFR — slow, full source):
#   explore-jar.sh lib.jar source com.example.MyClass      # full decompiled source

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT_DIR="$PLUGIN_ROOT/scripts"
CFR_JAR="$PLUGIN_ROOT/tools/cfr.jar"
VINEFLOWER_JAR="$PLUGIN_ROOT/tools/vineflower.jar"

source "$SCRIPT_DIR/resolve-java.sh"
source "$SCRIPT_DIR/read-settings.sh"
PROVIDER=$(read_provider)

JAR_PATH="${1:?Usage: explore-jar.sh <jar-path> <mode> [criteria]}"
MODE="${2:?Modes: class, package, search, method, source, list}"
CRITERIA="${3:-}"

if [[ ! -f "$JAR_PATH" ]]; then
  echo "ERROR: JAR not found: $JAR_PATH" >&2
  exit 1
fi

# Resolve JDK tools
JAVAP_CMD=$(resolve_jdk_tool javap)

# Cache for CFR decompilation
CACHE_BASE="${TMPDIR:-${TEMP:-/tmp}}/jar-explorer-cache"
JAR_HASH=$(md5sum "$JAR_PATH" 2>/dev/null | cut -d' ' -f1 || echo "nohash")
CACHE_DIR="$CACHE_BASE/$JAR_HASH/$PROVIDER"

CFR_FLAGS=(--silent true --comments false --decodelambdas true --sugarasserts true)

# Fast: javap class inspection (instant)
inspect_class() {
  local fqcn="$1"
  "$JAVAP_CMD" -cp "$JAR_PATH" -p "$fqcn" 2>/dev/null || {
    echo "ERROR: Failed to inspect $fqcn" >&2
    return 1
  }
}

# Try extracting original source from -sources.jar (Maven)
extract_from_sources_jar() {
  local fqcn="$1"
  local sources_jar="${JAR_PATH%.jar}-sources.jar"
  [[ -f "$sources_jar" ]] || return 1
  local rel_path="${fqcn//./\/}.java"
  unzip -p "$sources_jar" "$rel_path" 2>/dev/null || return 1
}

# Extract all .java files from -sources.jar for search-source mode
extract_all_sources_jar() {
  local sources_jar="${JAR_PATH%.jar}-sources.jar"
  [[ -f "$sources_jar" ]] || return 1
  local sources_dir="$CACHE_DIR/sources-jar"
  if [[ ! -d "$sources_dir" ]]; then
    mkdir -p "$sources_dir"
    unzip -qo "$sources_jar" -d "$sources_dir" 2>/dev/null || return 1
  fi
  echo "$sources_dir"
}

# Slow: full decompilation (for source mode)
decompile_class() {
  local fqcn="$1"

  # Try original source from -sources.jar first
  local src_output
  if src_output=$(extract_from_sources_jar "$fqcn" 2>/dev/null) && [[ -n "$src_output" ]]; then
    echo "# Source: $(basename "${JAR_PATH%.jar}-sources.jar") (original source)" >&2
    echo "$src_output"
    return 0
  fi

  mkdir -p "$CACHE_DIR"
  local cache_file="$CACHE_DIR/${fqcn}.java"

  if [[ -f "$cache_file" ]]; then
    echo "# Source: decompiled with $PROVIDER (cached)" >&2
    cat "$cache_file"
    return
  fi

  echo "# Source: decompiled with $PROVIDER" >&2
  if [[ "$PROVIDER" == "vineflower" ]]; then
    full_decompile
    local rel_path="${fqcn//./\/}.java"
    local vf_file="$CACHE_DIR/$rel_path"
    if [[ -f "$vf_file" ]]; then
      cp "$vf_file" "$cache_file"
      cat "$vf_file"
    else
      echo "ERROR: Decompiled file not found for $fqcn" >&2
      return 1
    fi
  else
    bash "$SCRIPT_DIR/setup-cfr.sh"
    local filter="^${fqcn//./\\.}$"
    local output
    output=$(java -jar "$CFR_JAR" "$JAR_PATH" --jarfilter "$filter" "${CFR_FLAGS[@]}" 2>/dev/null) || {
      echo "ERROR: Failed to decompile $fqcn" >&2
      return 1
    }
    echo "$output" > "$cache_file"
    echo "$output"
  fi
}

full_decompile() {
  mkdir -p "$CACHE_DIR"
  local marker="$CACHE_DIR/.full-decompile"
  if [[ -f "$marker" ]]; then
    return 0
  fi

  if [[ "$PROVIDER" == "vineflower" ]]; then
    bash "$SCRIPT_DIR/setup-vineflower.sh"
    echo "Decompiling entire JAR with Vineflower (this may take a moment)..." >&2
    java -jar "$VINEFLOWER_JAR" "$JAR_PATH" "$CACHE_DIR" >/dev/null 2>&1 || {
      echo "ERROR: Vineflower decompilation failed" >&2
      return 1
    }
  else
    bash "$SCRIPT_DIR/setup-cfr.sh"
    echo "Decompiling entire JAR (this may take a moment)..." >&2
    java -jar "$CFR_JAR" "$JAR_PATH" --outputdir "$CACHE_DIR" "${CFR_FLAGS[@]}" >/dev/null 2>&1 || {
      echo "ERROR: Full decompilation failed" >&2
      return 1
    }
  fi
  touch "$marker"
}

case "$MODE" in
  class)
    # Fast: javap signatures (instant)
    if [[ -z "$CRITERIA" ]]; then
      echo "ERROR: class mode requires a fully qualified class name" >&2
      exit 1
    fi
    echo "=== $CRITERIA ==="
    echo ""
    inspect_class "$CRITERIA"
    ;;

  source)
    # Slow: CFR full decompilation
    if [[ -z "$CRITERIA" ]]; then
      echo "ERROR: source mode requires a fully qualified class name" >&2
      exit 1
    fi
    echo "=== Source: $CRITERIA ==="
    echo ""
    decompile_class "$CRITERIA"
    ;;

  package)
    # Fast: javap signatures for all classes in package
    if [[ -z "$CRITERIA" ]]; then
      echo "ERROR: package mode requires a package name" >&2
      exit 1
    fi
    CLASSES=$(bash "$SCRIPT_DIR/list-jar.sh" "$JAR_PATH" "$CRITERIA" | head -50)
    if [[ -z "$CLASSES" ]]; then
      echo "No classes found in package '$CRITERIA'"
      exit 0
    fi

    COUNT=$(echo "$CLASSES" | wc -l)
    echo "=== Package: $CRITERIA ($COUNT classes) ==="
    echo ""

    echo "$CLASSES" | while IFS= read -r fqcn; do
      echo "--- $fqcn ---"
      inspect_class "$fqcn" || true
      echo ""
    done

    if [[ $COUNT -gt 50 ]]; then
      echo "... showing first 50 of $COUNT classes."
    fi
    ;;

  method)
    # Fast: javap + grep for method name
    if [[ -z "$CRITERIA" ]]; then
      echo "ERROR: method mode requires ClassName#methodName or just a method name" >&2
      exit 1
    fi
    if [[ "$CRITERIA" == *"#"* ]]; then
      FQCN="${CRITERIA%%#*}"
      METHOD="${CRITERIA##*#}"
      echo "=== $FQCN — methods matching '$METHOD' ==="
      echo ""
      inspect_class "$FQCN" | grep -i "$METHOD" || echo "No methods matching '$METHOD'"
    else
      # Search method name across all classes — use list + javap
      echo "=== Searching for method '$CRITERIA' ==="
      echo ""
      CLASSES=$(bash "$SCRIPT_DIR/list-jar.sh" "$JAR_PATH")
      echo "$CLASSES" | while IFS= read -r fqcn; do
        MATCH=$("$JAVAP_CMD" -cp "$JAR_PATH" -p "$fqcn" 2>/dev/null | grep -i "$CRITERIA" || true)
        if [[ -n "$MATCH" ]]; then
          echo "--- $fqcn ---"
          echo "$MATCH"
          echo ""
        fi
      done
    fi
    ;;

  search)
    # Hybrid: search javap signatures first, then CFR full source
    if [[ -z "$CRITERIA" ]]; then
      echo "ERROR: search mode requires a search term" >&2
      exit 1
    fi

    echo "=== Search: '$CRITERIA' ==="
    echo ""

    # Phase 1: Fast signature search
    echo "--- Signature matches (fast) ---"
    echo ""
    CLASSES=$(bash "$SCRIPT_DIR/list-jar.sh" "$JAR_PATH")
    SIG_FOUND=false
    echo "$CLASSES" | while IFS= read -r fqcn; do
      MATCH=$("$JAVAP_CMD" -cp "$JAR_PATH" -p "$fqcn" 2>/dev/null | grep -i "$CRITERIA" || true)
      if [[ -n "$MATCH" ]]; then
        echo "$fqcn:"
        echo "$MATCH"
        echo ""
      fi
    done

    # Phase 2: If user needs source-level search, suggest it
    echo ""
    echo "Tip: For full source-level search, use: explore-jar.sh <jar> search-source \"$CRITERIA\""
    ;;

  search-source)
    # Slow: full decompile + grep (only when explicitly requested)
    if [[ -z "$CRITERIA" ]]; then
      echo "ERROR: search-source mode requires a search term" >&2
      exit 1
    fi

    # Try sources JAR first
    SEARCH_DIR=""
    SRC_DIR=""
    if SRC_DIR=$(extract_all_sources_jar 2>/dev/null) && [[ -d "$SRC_DIR" ]]; then
      echo "# Source: $(basename "${JAR_PATH%.jar}-sources.jar") (original source)" >&2
      SEARCH_DIR="$SRC_DIR"
    else
      full_decompile
      echo "# Source: decompiled with $PROVIDER" >&2
      SEARCH_DIR="$CACHE_DIR"
    fi

    echo "=== Source search: '$CRITERIA' ==="
    echo ""

    RESULTS=$(grep -rl "$CRITERIA" "$SEARCH_DIR" --include="*.java" 2>/dev/null | head -20 || true)
    if [[ -z "$RESULTS" ]]; then
      echo "No matches found for '$CRITERIA'"
      exit 0
    fi

    RESULT_COUNT=$(echo "$RESULTS" | wc -l)
    echo "Found $RESULT_COUNT file(s):"
    echo ""

    echo "$RESULTS" | while IFS= read -r file; do
      REL_PATH="${file#$SEARCH_DIR/}"
      echo "--- $REL_PATH ---"
      grep -n "$CRITERIA" "$file" -B 2 -A 5 2>/dev/null | head -40 || true
      echo ""
    done
    ;;

  list)
    echo "=== JAR Contents: $(basename "$JAR_PATH") ==="
    echo ""
    bash "$SCRIPT_DIR/list-jar.sh" "$JAR_PATH" "${CRITERIA:-}"
    ;;

  *)
    echo "ERROR: Unknown mode '$MODE'. Use: class, package, search, method, source, list" >&2
    exit 1
    ;;
esac
