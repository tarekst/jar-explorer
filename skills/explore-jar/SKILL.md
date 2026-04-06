---
name: explore-jar
description: Explore Java JAR files — search classes, packages, methods, decompile source
allowed-tools: Bash, Read, Grep, Glob
argument-hint: <class-name> [jar-hint] [class|source]
model: claude-sonnet-4-6
---

# Explore JAR

Explore a Java JAR file using javap (fast signatures) or CFR (full decompilation).

## Quick Lookup (preferred — one call does everything)

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-explore.sh "$0" "$1" "$2"`
```

- `$0` — Class name (e.g. `FileUtils`) or FQCN (e.g. `org.apache.commons.io.FileUtils`)
- `$1` — JAR hint (e.g. `commons-io`, `guava`) — optional, speeds up search
- `$2` — Mode: `class` (default, javap) or `source` (CFR decompile)

## Advanced Usage

For package browsing, search, or when you have the full JAR path, use these commands manually:

First resolve the JAR:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/find-jar.sh "<artifact-hint>"
```

Then explore:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/explore-jar.sh "<jar-path>" "<mode>" "<criteria>"
```

## Modes

| Mode | Speed | Description |
|------|-------|-------------|
| `class` | instant | javap signatures — fields, methods, types |
| `package` | instant | javap signatures for all classes in package |
| `method` | fast | Find method by name |
| `search` | fast | Search across signatures |
| `list` | instant | List all classes in JAR |
| `source` | slow | Full CFR decompilation |

## Provider Setting

Use `/jar-explorer:set-provider <native|vineflower>` to switch the decompiler backend.
- `native` (default): CFR for decompilation
- `vineflower`: Vineflower for decompilation

## Examples

- `/jar-explorer:explore-jar FileUtils commons-io` — Show FileUtils signatures
- `/jar-explorer:explore-jar ImmutableList guava source` — Full source
- `/jar-explorer:explore-jar org.apache.commons.io.FileUtils` — FQCN lookup
