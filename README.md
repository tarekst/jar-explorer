# JAR Explorer

A Claude Code plugin that explores Java JAR files. Uses `javap` for instant method/field signatures and a configurable decompiler (CFR or Vineflower) for full source.

## Prerequisites

- **Java JDK** installed (javap + jar must be available)
- **curl** for downloading decompilers (first use of `source` mode only)

## Installation

```bash
claude --plugin-dir /path/to/jar-explorer
```

## Documentation

### Quick Start

```
/jar-explorer:explore-jar FileUtils commons-io          # class signatures (javap)
/jar-explorer:explore-jar ImmutableList guava source     # full source code
/jar-explorer:explore-jar org.apache.commons.io.FileUtils  # FQCN lookup
```

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/jar-explorer:explore-jar` | `<class-name> [jar-hint] [class\|source]` | Look up a class by simple name or FQCN |
| `/jar-explorer:set-provider` | `<native\|vineflower>` | Switch the decompiler backend |

### Modes

The quick lookup (`explore-jar`) supports `class` (default) and `source`. For advanced modes, use `explore-jar.sh` directly with a resolved JAR path:

| Mode | Speed | Description | Example criteria |
|------|-------|-------------|------------------|
| `class` | instant | javap signatures — fields, methods, types | `com.example.MyClass` |
| `package` | instant | javap signatures for all classes in a package (max 50) | `com.example.util` |
| `method` | fast | Find methods by name across classes | `Foo#bar` or `bar` |
| `search` | fast | Search across javap signatures | `"BeanFactory"` |
| `list` | instant | List all classes in the JAR | optional filter |
| `source` | slow | Full decompilation of a single class | `com.example.MyClass` |
| `search-source` | slow | Full decompile + grep across all source | `"keyword"` |

### JAR Resolution

The plugin resolves JAR files in multiple ways:

| Input format | Example | Search scope |
|-------------|---------|-------------|
| Direct path | `./lib/mylib.jar` | File system |
| Maven coordinate | `org.springframework:spring-core:6.1.0` | `~/.m2/repository` |
| Partial name | `guava`, `commons-io` | `~/.m2`, `~/.gradle`, CWD |

When using a partial name, the plugin also parses POM files of matching JARs to search transitive dependencies.

### Source Lookup Priority

When `source` mode is requested, the plugin tries three strategies in order:

1. **Sources JAR** — looks for a `-sources.jar` next to the bytecode JAR (original source with comments and variable names)
2. **Decompiler** — falls back to CFR or Vineflower to reconstruct source from bytecode
3. **Cache** — previously decompiled results are served instantly from disk

A stderr hint indicates the source provenance (`original source` vs `decompiled with CFR/Vineflower`).

### Decompiler Providers

| Provider | Decompiler | Behavior |
|----------|-----------|----------|
| `native` (default) | CFR | Extracts single classes on demand — fast per-class, no upfront cost |
| `vineflower` | Vineflower | Decompiles entire JAR on first request — slower initially, instant for subsequent classes |

Both providers use `javap` for signature modes (`class`, `package`, `method`, `search`). The provider setting only affects `source` and `search-source` modes.

### Agent

The `explore-jar` agent (Sonnet, max 5 turns) triggers automatically when Claude encounters JAR dependencies during code exploration. It prefers fast `javap` signatures and only decompiles when the user explicitly requests source code. Limited to 3 Bash calls per request.

### Caching

| What | Location | TTL |
|------|----------|-----|
| JAR index | `$TMPDIR/jar-explorer-cache/jar-index.txt` | 1 hour |
| Decompiled classes | `$TMPDIR/jar-explorer-cache/<jar-md5>/<provider>/` | permanent |
| Sources JAR extraction | `$TMPDIR/jar-explorer-cache/<jar-md5>/<provider>/sources-jar/` | permanent |

Each provider has its own cache directory. Switching providers does not invalidate the other's cache.

## How It Works

1. **javap** (JDK built-in) reads method/field signatures directly from bytecode — instant, no decompilation
2. **Decompiler** (CFR or Vineflower) reconstructs full Java source from bytecode — slower, used only for `source` mode
3. **Sources JAR** — if a `-sources.jar` exists next to the bytecode JAR (common in Maven repos), original source is used instead of decompiling
4. JAR contents are listed with `jar tf` (instant)
5. Decompilation results are cached per JAR hash and provider in the system temp directory

## Credits

- **[CFR](https://github.com/leibnitz27/cfr)** by Lee Benfield — Java decompiler (default provider)
- **[Vineflower](https://github.com/Vineflower/vineflower)** — modern Fernflower fork (alternative provider)
