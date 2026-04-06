# Changelog

## 0.1.1 (2026-04-06)

### Added

- Plugin manifest fields: `license`, `repository`, `homepage`, author `email` and `url`
- `set -euo pipefail` in sourced scripts (`resolve-java.sh`, `read-settings.sh`)
- Model overrides for skills: Sonnet for `explore-jar`, Haiku for `set-provider`
- `maxTurns: 5` and `effort: medium` in `explore-jar` agent
- `CLAUDE.md` tracked in git (architecture documentation)
- `CHANGELOG.md`

### Changed

- README.md: replaced Usage section with comprehensive Documentation section (Quick Start, Commands, Modes, JAR Resolution, Source Lookup Priority, Decompiler Providers, Agent, Caching)
- `LICENSE.txt` renamed to `LICENSE` (convention)

## 0.1.0 (2026-04-01)

Initial release.

- Three-tier JAR exploration: javap (signatures), sources JAR (original source), decompiler (CFR/Vineflower)
- Quick class lookup with automatic JAR discovery (`quick-explore.sh`)
- Multi-mode exploration: class, package, method, search, source, search-source, list
- Configurable decompiler backend (native/CFR or Vineflower)
- POM-based transitive dependency search
- Per-JAR, per-provider caching
- Windows/Git Bash path compatibility
- MIT license
