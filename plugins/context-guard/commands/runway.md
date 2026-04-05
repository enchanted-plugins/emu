---
name: allay:runway
description: >
  Quick runway check. How many turns until compaction?
  Use when you want a fast answer without full report.
---

When the user runs `/allay:runway`:

1. Read the last 5 entries from `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl`.
2. Calculate average tokens per turn from the recent data.
3. Estimate remaining turns until compaction.

## Output Format

```
⚠️ RUNWAY: ~[N] turns remaining | [V] tokens/turn avg
```

If no data is available: "No metrics yet. Runway estimate available after 5+ turns."
