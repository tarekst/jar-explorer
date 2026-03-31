---
name: set-provider
description: Switch the decompiler provider (native or vineflower)
allowed-tools: Bash
argument-hint: <native|vineflower>
---

# Set Decompiler Provider

Switch between decompiler backends.

- `native` (default): javap for signatures, CFR for full decompilation
- `vineflower`: javap for signatures, Vineflower for full decompilation

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/set-provider.sh "$0"`
```
