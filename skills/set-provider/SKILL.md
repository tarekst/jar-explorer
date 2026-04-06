---
name: set-provider
description: Switch the decompiler provider (native or vineflower)
allowed-tools: Bash
argument-hint: <native|vineflower>
model: claude-haiku-4-5-20251001
---

# Set Decompiler Provider

Switch between decompiler backends.

- `native` (default): javap for signatures, CFR for full decompilation
- `vineflower`: javap for signatures, Vineflower for full decompilation

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/set-provider.sh "$0"`
```
