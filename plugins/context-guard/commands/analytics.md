---
name: allay:analytics
description: >
  Per-tool token analytics for the current session.
  Shows which tools consume the most tokens and suggests optimizations.
---

When the user runs `/allay:analytics`:

## Data Source

Read `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` and look for `{"event":"turn"}` entries.
Each turn entry has: `tool` (tool name), `tokens_est` (estimated tokens), `turn` (turn number).

Use `grep "\"event\":\"turn\"" metrics.jsonl` to pre-filter (never `jq -s`).

## Calculations

1. **Per-tool aggregation**: Group turn entries by `tool`. For each tool, count calls and sum `tokens_est`.
2. **Top consumers**: Find the 3 tool+target combinations consuming the most tokens. Include specific file paths or commands where available from the drift cache at `/tmp/allay-drift-*.jsonl`.
3. **Session totals**: Sum all `tokens_est`. Estimate remaining from 200K context window.
4. **Savings credit**: Cross-reference with `duplicate_blocked` and `bash_compressed` events to show tokens saved.

## Output Format

```
TOOL ANALYTICS (this session)
  Read:    [N] calls, ~[T] tokens ([P]%)
  Bash:    [N] calls, ~[T] tokens ([P]%)
  Write:   [N] calls, ~[T] tokens ([P]%)
  Edit:    [N] calls, ~[T] tokens ([P]%)
  Grep:    [N] calls, ~[T] tokens ([P]%)
  Glob:    [N] calls, ~[T] tokens ([P]%)

  TOP CONSUMERS:
  1. [Tool] [target] ([N] calls, ~[T] tokens) — [suggestion]
  2. [Tool] [target] ([N] calls, ~[T] tokens) — [suggestion]
  3. [Tool] [target] ([N] calls, ~[T] tokens) — [suggestion]

  SESSION: ~[T] tokens used, ~[R] remaining (~[N] turns at current rate)
```

## Suggestions

Generate actionable suggestions based on patterns:
- Repeated Read of same file → "suggest: use Grep for specific lines"
- Bash with verbose output → "suggest: add --reporter=dot for terse output"
- Duplicate reads blocked → "BLOCKED by token-saver (saved ~[T] tokens)"
- High Glob/Grep count on same path → "suggest: narrow your search pattern"

## Rules

1. Show "No analytics data yet. Run a few tool calls first." if no turn events exist.
2. Only show tools that have at least 1 call.
3. Sort tools by total tokens (descending).
4. Percentages should sum to 100% (round last entry to compensate).
5. Never fabricate data — only report what metrics.jsonl contains.
