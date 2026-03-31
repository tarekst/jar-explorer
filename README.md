# JAR Explorer

A Claude Code plugin that explores Java JAR files. Uses `javap` for instant method/field signatures and a configurable decompiler (CFR or Vineflower) for full source.

## Prerequisites

- **Java JDK** installed (javap + jar must be available)
- **curl** for downloading decompilers (first use of `source` mode only)

## Installation

```bash
claude --plugin-dir /path/to/jar-explorer
```

## Usage

### Command

```
/jar-explorer:explore-jar <class-name> [jar-hint] [class|source]
```

### Modes

| Mode | Speed | Example | Description |
|------|-------|---------|-------------|
| `list` | instant | `... guava list` | List all classes |
| `class` | instant | `... guava class com.google.common.collect.ImmutableList` | javap signatures (methods, fields, types) |
| `package` | instant | `... spring-core package org.springframework.util` | Signatures for all classes in package |
| `method` | fast | `... mylib.jar method com.example.Foo#bar` | Find method by name |
| `search` | fast | `... mylib.jar search "BeanFactory"` | Search across signatures |
| `source` | slow | `... guava source com.google.common.collect.ImmutableList` | Full decompilation |
| `search-source` | slow | `... mylib.jar search-source "keyword"` | Full source-level search |

**JAR resolution:**
- Direct path: `./lib/mylib.jar`
- Maven coordinate: `org.springframework:spring-core:6.1.0`
- Partial name: `guava` (searches ~/.m2, ~/.gradle, CWD)

### Decompiler Provider

Switch between decompiler backends:

```
/jar-explorer:set-provider <native|vineflower>
```

| Provider | Decompiler | Behavior |
|----------|-----------|----------|
| `native` (default) | CFR | Extracts single classes on demand — fast per-class, no upfront cost |
| `vineflower` | Vineflower | Decompiles entire JAR on first request — slower initially, instant for subsequent classes |

Both providers use `javap` for signature modes (`class`, `package`, `method`, `search`). The provider setting only affects `source` and `search-source` modes.

### Agent

The `explore-jar` agent triggers automatically when Claude needs to read JAR source code. It prefers fast `javap` modes and only falls back to the configured decompiler when full source is needed.

## How It Works

1. **javap** (JDK built-in) reads method/field signatures directly from bytecode — instant, no decompilation
2. **Decompiler** (CFR or Vineflower) reconstructs full Java source from bytecode — slower, used only for `source` mode
3. **Sources JAR** — if a `-sources.jar` exists next to the bytecode JAR (common in Maven repos), original source is used instead of decompiling
4. JAR contents are listed with `jar tf` (instant)
5. Decompilation results are cached per JAR hash and provider in the system temp directory

## Credits

- **[CFR](https://github.com/leibnitz27/cfr)** by Lee Benfield — Java decompiler (default provider)
- **[Vineflower](https://github.com/Vineflower/vineflower)** — modern Fernflower fork (alternative provider)
