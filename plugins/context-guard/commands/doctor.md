---
name: allay:doctor
description: Diagnostic self-check for all Allay plugins.
---

When the user runs `/allay:doctor`, perform a diagnostic check on the Allay installation:

## Checks

1. **[jq]** — Is jq installed and accessible?
2. **[state-keeper]** — Is the hook script executable? Is state/ writable? Is metrics.jsonl valid JSON lines?
3. **[token-saver]** — Are both hook scripts (compress-bash.sh, block-duplicates.sh) executable?
4. **[context-guard]** — Is detect-drift.sh executable? Is /tmp/ writable? Can session cache files be created?

## Output Format

Show `[✓]` or `[✗]` per check. For failures, include a fix command:

```
Allay Doctor
────────────────────────────
[✓] jq installed (v1.7)
[✓] state-keeper hook executable
[✓] state-keeper state/ writable
[✗] token-saver compress-bash.sh not executable
    Fix: chmod +x plugins/token-saver/hooks/pre-tool-use/compress-bash.sh
[✓] context-guard detect-drift.sh executable
[✓] /tmp/ writable
────────────────────────────
5/6 checks passed
```

## Plugin Paths

Use `${CLAUDE_PLUGIN_ROOT}/..` to find sibling plugins:
- `${CLAUDE_PLUGIN_ROOT}/../state-keeper/`
- `${CLAUDE_PLUGIN_ROOT}/../token-saver/`
- `${CLAUDE_PLUGIN_ROOT}/` (self)
