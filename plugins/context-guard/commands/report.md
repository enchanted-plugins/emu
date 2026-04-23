---
name: fae:report
description: >
  Token savings + drift alert dashboard for this session.
  Aggregates metrics from all Emu plugins. Use after
  any session, before context gets low, or on request.
argument-hint: "[--global]"
---

When the user runs `/fae:report`, generate a session report by reading metrics from all Emu plugin state directories.

## Flags

- `--global` — A9 unified view across ALL worktrees of this repo. Reads from
  the XDG global dir (`${XDG_STATE_HOME:-~/.local/state}/fae/<repo_id>/`),
  merging every `skill-metrics-global.*.jsonl` shard. Shows one totals row
  that spans every concurrent Claude Code session on this repo.

## Data Sources

Default (no flag) — local session only:
- `${CLAUDE_PLUGIN_ROOT}/../state-keeper/state/metrics.jsonl`
- `${CLAUDE_PLUGIN_ROOT}/../token-saver/state/metrics.jsonl`
- `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` (context-guard's own drift data)
- `${CLAUDE_PLUGIN_ROOT}/state/skill-metrics.jsonl` (A8 skill attribution, if present)

`--global` — adds unified cross-worktree data:
- `${XDG_STATE_HOME:-~/.local/state}/fae/<repo_id>/skill-metrics-global.*.jsonl`
  (one shard per PID; read all, merge by `ts`)

## Output Format

```
══════════════════════════════════════
 FAE SESSION REPORT
══════════════════════════════════════

 ── Worktree Overview (A9) ───────────
 [shown only when >1 worktree has written to the global file this session]
 .                (main)     ~28,400 tokens   62%
 apps/sigil   (worktree)    ~17,200 tokens   38%
 ─────────────────────────────────────
 Total                       ~45,600 tokens

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
2. **Worktree Overview is ZEROTH (only when multi-worktree). Runway is FIRST. Drift is SECOND. Savings is THIRD.** This order is mandatory.
3. Never fabricate numbers — only show what metrics.jsonl contains.
4. Always show the methodology line.
5. For drift savings: count only if user changed approach within 3 turns after alert. Otherwise show "(no action taken)".
6. Use `grep` with pre-filter on metrics.jsonl — never `jq -s` (slurps entire file).
7. Token estimates use conservative multipliers:
   - Bash compression: ~2K tokens per compression
   - Duplicate read blocked: ~4K tokens per block
   - Drift intervention: ~800 tokens per unproductive turn avoided

## Worktree Overview rules (A9)

8. Only render the WORKTREE OVERVIEW section if `grep -hE '"worktree":"[^"]+"' $XDG_STATE_HOME/fae/<repo_id>/skill-metrics-global.*.jsonl | sort -u` returns 2+ distinct worktrees. A single-worktree session doesn't need it.
9. Rows sorted by token total descending.
10. The main worktree is labeled `(main)`. Everything else `(worktree)`. Label column is fixed-width.
11. `--global` flag forces the section to render, even if only one worktree is active, and additionally lists sessions observed in the global dir (not just the current one).
12. Token estimates in WORKTREE OVERVIEW are the SUM of `token_estimate` from the global shards per worktree. Percentages are of the cross-worktree total.
