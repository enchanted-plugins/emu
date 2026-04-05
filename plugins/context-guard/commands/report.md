---
name: allay:report
description: >
  Token savings + drift alert dashboard for this session.
  Aggregates metrics from all Allay plugins. Use after
  any session, before context gets low, or on request.
---

When the user runs `/allay:report`, generate a session report by reading metrics from all Allay plugin state directories.

## Data Sources

Read `state/metrics.jsonl` from all sibling plugin directories:
- `${CLAUDE_PLUGIN_ROOT}/../state-keeper/state/metrics.jsonl`
- `${CLAUDE_PLUGIN_ROOT}/../token-saver/state/metrics.jsonl`
- `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` (context-guard's own drift data)

## Output Format

```
══════════════════════════════════════
 ALLAY SESSION REPORT
══════════════════════════════════════

 Runway:  ~[N] turns until compaction
 Velocity: [V] tokens/turn avg

 ── Savings ──────────────────────────
 Checkpoints saved:        [N]
 Bash compressions:        [N]  → ~[X]K tokens
 Duplicate reads blocked:  [N]  → ~[X]K tokens
 Total estimated:          ~[X]K tokens

 ── Drift Alerts ─────────────────────
 Alerts fired:             [N]
 ├─ Read loop:    [file] ([N] reads)
 ├─ Edit-revert:  [file] ([N] cycles)
 └─ Fail loop:    [cmd] ([N] failures)

 Est. tokens saved by early intervention: ~[X]K
 (avg 800 tokens/unproductive turn × turns avoided)

 Session: [N] turns | [N] min
 Methodology: conservative multipliers.
══════════════════════════════════════
```

## Rules

1. Show "No data yet" if all metrics files are empty or missing.
2. **Runway is FIRST. Drift is SECOND. Savings is THIRD.** This order is mandatory.
3. Never fabricate numbers — only show what metrics.jsonl contains.
4. Always show the methodology line.
5. For drift savings: count only if user changed approach within 3 turns after alert. Otherwise show "(no action taken)".
6. Use `grep` with pre-filter on metrics.jsonl — never `jq -s` (slurps entire file).
7. Token estimates use conservative multipliers:
   - Bash compression: ~2K tokens per compression
   - Duplicate read blocked: ~4K tokens per block
   - Drift intervention: ~800 tokens per unproductive turn avoided
