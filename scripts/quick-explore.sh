#!/bin/bash
set -euo pipefail

# One-shot class lookup: find JAR → resolve FQCN → javap/CFR in one call.
#
# Usage:
#   quick-explore.sh <class-name-or-fqcn> [jar-hint] [mode]
#
# Examples:
#   quick-explore.sh OpenPGPCertificate                    # auto-find JAR, javap
#   quick-explore.sh org.bouncycastle.openpgp.api.OpenPGPCertificate  # FQCN, javap
#   quick-explore.sh OpenPGPCertificate bcpg-jdk18on       # with JAR hint
#   quick-explore.sh OpenPGPCertificate "" source           # CFR full source
#
# Modes: class (default, javap), source (CFR decompile)

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT_DIR="$PLUGIN_ROOT/scripts"

source "$SCRIPT_DIR/resolve-java.sh"
source "$SCRIPT_DIR/read-settings.sh"
PROVIDER=$(read_provider)

INPUT="${1:?Usage: quick-explore.sh <class-name-or-fqcn> [jar-hint] [mode]}"
JAR_HINT="${2:-}"
MODE="${3:-class}"

JAVAP_CMD=$(resolve_jdk_tool javap)
JAR_CMD=$(resolve_jdk_tool jar)

CACHE_BASE="${TMPDIR:-${TEMP:-/tmp}}/jar-explorer-cache"
INDEX_FILE="$CACHE_BASE/jar-index.txt"
mkdir -p "$CACHE_BASE"

# --- JAR Index ---
build_index() {
  local dirs=()
  [[ -d "$HOME/.m2/repository" ]] && dirs+=("$HOME/.m2/repository")
  [[ -d "$HOME/.gradle/caches" ]] && dirs+=("$HOME/.gradle/caches")

  if [[ ${#dirs[@]} -eq 0 ]]; then
    touch "$INDEX_FILE"
    return
  fi

  find "${dirs[@]}" -name "*.jar" \
    -not -name "*-sources*" \
    -not -name "*-javadoc*" \
    -type f 2>/dev/null > "$INDEX_FILE" || true
}

ensure_index() {
  if [[ ! -f "$INDEX_FILE" ]]; then
    build_index
    return
  fi
  # Rebuild if older than 1 hour
  local age
  if stat --version &>/dev/null 2>&1; then
    # GNU stat
    age=$(( $(date +%s) - $(stat -c %Y "$INDEX_FILE" 2>/dev/null || echo 0) ))
  else
    # BSD/macOS stat
    age=$(( $(date +%s) - $(stat -f %m "$INDEX_FILE" 2>/dev/null || echo 0) ))
  fi
  if [[ $age -gt 3600 ]]; then
    build_index
  fi
}

# --- Search JARs for a class file pattern ---
search_jars() {
  local pattern="$1"
  local candidates="$2"
  local limit="${3:-30}"
  local jar
  while IFS= read -r jar; do
    [[ -z "$jar" ]] && continue
    if "$JAR_CMD" tf "$jar" 2>/dev/null | grep -q "$pattern"; then
      echo "$jar"
      return 0
    fi
  done < <(echo "$candidates" | sort -rV | head -"$limit")
  return 1
}

# --- Find JAR containing a class ---
find_jar_for_class() {
  local class_name="$1"
  local hint="${2:-}"

  # If hint looks like a file path, try it directly
  if [[ -f "$hint" ]]; then
    echo "$hint"
    return 0
  fi

  ensure_index

  # Extract simple class name (always useful as fallback)
  local simple_name
  if [[ "$class_name" == *.* ]]; then
    simple_name="${class_name##*.}"
  else
    simple_name="$class_name"
  fi
  local simple_pattern="/${simple_name}.class"

  # --- Phase 1: Narrow candidates by hint ---
  local candidates=""
  local search_limit=30
  if [[ -n "$hint" ]]; then
    candidates=$(grep -i "$hint" "$INDEX_FILE" 2>/dev/null || true)
  elif [[ "$class_name" == *.* ]]; then
    # FQCN: extract package parts as hints
    local pkg_parts
    pkg_parts=$(echo "$class_name" | tr '.' '\n' | grep -v '^org$\|^com$\|^net$\|^io$\|^java$\|^javax$' | head -3)
    for part in $pkg_parts; do
      candidates=$(grep -i "$part" "$INDEX_FILE" 2>/dev/null || true)
      [[ -n "$candidates" ]] && break
    done
  else
    # No hint, no FQCN: try to derive hint from class name
    # Split CamelCase into words and search index for each
    local derived_parts
    derived_parts=$(echo "$simple_name" | sed 's/\([a-z]\)\([A-Z]\)/\1\n\2/g' | tr '[:upper:]' '[:lower:]')
    for part in $derived_parts; do
      [[ ${#part} -lt 3 ]] && continue
      candidates=$(grep -i "$part" "$INDEX_FILE" 2>/dev/null || true)
      [[ -n "$candidates" ]] && break
    done
    # Final fallback: search entire index
    if [[ -z "$candidates" ]]; then
      candidates=$(cat "$INDEX_FILE" 2>/dev/null || true)
      search_limit=100
    fi
  fi

  if [[ -z "$candidates" ]]; then
    echo "ERROR: Cannot find JAR for '$class_name'." >&2
    echo "Provide a jar-hint as second argument." >&2
    return 1
  fi

  # --- Phase 2: Search exact FQCN first ---
  if [[ "$class_name" == *.* ]]; then
    local exact_pattern="${class_name//./\/}.class"
    local result
    result=$(search_jars "$exact_pattern" "$candidates" "$search_limit") && { echo "$result"; return 0; }
  fi

  # --- Phase 3: Fallback to simple name search in same candidates ---
  local result
  result=$(search_jars "$simple_pattern" "$candidates" "$search_limit") && { echo "$result"; return 0; }

  # --- Phase 4: Search transitive dependencies via POM ---
  # Parse POM files of candidate JARs to find transitive dependency JARs
  local pom_deps=""
  while IFS= read -r jar; do
    [[ -z "$jar" ]] && continue
    local pom="${jar%.jar}.pom"
    [[ ! -f "$pom" ]] && continue
    # Extract groupId:artifactId:version from POM dependencies
    local deps
    deps=$(grep -A 5 '<dependency>' "$pom" 2>/dev/null \
      | grep -E '<(groupId|artifactId|version)>' \
      | sed 's|^[[:space:]]*||; s|<[^>]*>||g; s|[[:space:]]*$||' \
      | paste -d: - - - 2>/dev/null || true)
    while IFS=: read -r g a v; do
      [[ -z "$g" || -z "$a" || -z "$v" ]] && continue
      local dep_path="$HOME/.m2/repository/${g//./\/}/$a/$v/$a-$v.jar"
      [[ -f "$dep_path" ]] && pom_deps="$pom_deps"$'\n'"$dep_path"
    done <<< "$deps"
  done < <(echo "$candidates" | sort -rV | head -5)

  if [[ -n "$pom_deps" ]]; then
    result=$(search_jars "$simple_pattern" "$pom_deps") && { echo "$result"; return 0; }
  fi

  echo "ERROR: Class '$simple_name' not found in hinted JARs or their dependencies." >&2
  echo "Try: quick-explore.sh $simple_name <jar-hint> (e.g. library name like guava, commons-io, spring-web)" >&2
  return 1
}

# --- Resolve FQCN from JAR ---
resolve_fqcn() {
  local jar="$1"
  local class_name="$2"

  # Extract simple name
  local simple_name
  if [[ "$class_name" == *.* ]]; then
    simple_name="${class_name##*.}"
  else
    simple_name="$class_name"
  fi

  # Always search by simple name in the JAR to get the actual FQCN
  # (the input FQCN might be wrong/guessed)
  local match
  match=$("$JAR_CMD" tf "$jar" 2>/dev/null \
    | grep "/${simple_name}.class$" \
    | grep -v '\$' \
    | head -1 \
    | sed 's|/|.|g; s|\.class$||')

  if [[ -z "$match" ]]; then
    echo "ERROR: Class '$simple_name' not found in $(basename "$jar")" >&2
    return 1
  fi

  echo "$match"
}

# --- Main ---

# Step 1: Find the JAR
JAR_PATH=$(find_jar_for_class "$INPUT" "$JAR_HINT") || exit 1

# Step 2: Resolve FQCN
FQCN=$(resolve_fqcn "$JAR_PATH" "$INPUT") || exit 1

echo "=== $FQCN ==="
echo "JAR: $(basename "$JAR_PATH")"
echo ""

# Step 3: Inspect or decompile
case "$MODE" in
  class)
    "$JAVAP_CMD" -cp "$JAR_PATH" -p "$FQCN" 2>/dev/null || {
      echo "ERROR: javap failed for $FQCN" >&2
      exit 1
    }
    ;;
  source)
    # Try original source from -sources.jar first
    SOURCES_JAR="${JAR_PATH%.jar}-sources.jar"
    if [[ -f "$SOURCES_JAR" ]]; then
      REL_PATH="${FQCN//./\/}.java"
      SRC_OUTPUT=$(unzip -p "$SOURCES_JAR" "$REL_PATH" 2>/dev/null) || true
      if [[ -n "$SRC_OUTPUT" ]]; then
        echo "# Source: $(basename "$SOURCES_JAR") (original source)" >&2
        echo "$SRC_OUTPUT"
        exit 0
      fi
    fi

    # Fallback: decompiler
    echo "# Source: decompiled with $PROVIDER" >&2
    if [[ "$PROVIDER" == "vineflower" ]]; then
      bash "$SCRIPT_DIR/setup-vineflower.sh" 2>/dev/null
      VF_JAR="$PLUGIN_ROOT/tools/vineflower.jar"
      VF_CACHE="${TMPDIR:-${TEMP:-/tmp}}/jar-explorer-cache"
      VF_HASH=$(md5sum "$JAR_PATH" 2>/dev/null | cut -d' ' -f1 || echo "nohash")
      VF_DIR="$VF_CACHE/$VF_HASH/vineflower"
      VF_MARKER="$VF_DIR/.full-decompile"
      if [[ ! -f "$VF_MARKER" ]]; then
        mkdir -p "$VF_DIR"
        java -jar "$VF_JAR" "$JAR_PATH" "$VF_DIR" >/dev/null 2>&1 || {
          echo "ERROR: Vineflower decompilation failed for $FQCN" >&2
          exit 1
        }
        touch "$VF_MARKER"
      fi
      VF_REL="${FQCN//./\/}.java"
      cat "$VF_DIR/$VF_REL" 2>/dev/null || {
        echo "ERROR: Decompiled source not found for $FQCN" >&2
        exit 1
      }
    else
      bash "$SCRIPT_DIR/setup-cfr.sh" 2>/dev/null
      CFR_JAR="$PLUGIN_ROOT/tools/cfr.jar"
      FILTER="^${FQCN//./\\.}$"
      java -jar "$CFR_JAR" "$JAR_PATH" --jarfilter "$FILTER" \
        --silent true --comments false --decodelambdas true --sugarasserts true 2>/dev/null || {
        echo "ERROR: CFR decompilation failed for $FQCN" >&2
        exit 1
      }
    fi
    ;;
  *)
    echo "ERROR: Unknown mode '$MODE'. Use: class, source" >&2
    exit 1
    ;;
esac
