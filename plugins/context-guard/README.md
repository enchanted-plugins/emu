# context-guard

**The eyes of Emu.**

**Hook type:** PostToolUse — fires after every tool call.

## Install

Part of the [Emu](../..) bundle. The simplest install is the `full` meta-plugin, which pulls in all 3 Emu plugins via dependency resolution:

```
/plugin marketplace add enchanted-plugins/fae
/plugin install full@fae
```

To install this plugin on its own: `/plugin install fae-context-guard@fae`. `context-guard` surfaces drift and runway using signals that only exist because `state-keeper` checkpoints before compaction and `token-saver` compresses outputs — so on its own the dashboard has thin data to report.

## Components

| Type | Name | Description |
|------|------|-------------|
| Hook | detect-drift.sh | Drift detection + token estimation on every tool call |
| Skill | drift-awareness | Guides user out of unproductive loops |
| Skill | token-awareness | Runway monitoring and token efficiency advice |
| Command | /fae:report | Full session dashboard (Runway → Drift → Savings) |
| Command | /fae:runway | Quick turns-until-compaction check |
| Command | /fae:analytics | Per-tool token consumption breakdown |
| Command | /fae:doctor | Diagnostic self-check for all plugins |
| Agent | analyst | Background report generation (Haiku, forked) |
| Agent | forecaster | Runway forecast with confidence interval (Haiku, forked) |

## Architecture

```
PostToolUse (Bash|Read|Write|Edit|MultiEdit|Glob|Grep)
    │
    ▼
detect-drift.sh
    │
    ├── Extract tool data (file path, hash, command, exit code)
    ├── Append to session cache (/tmp/fae-drift-*.jsonl)
    ├── Estimate tokens (input + result bytes)
    ├── Log turn event to state/metrics.jsonl
    ├── Check cooldown
    └── Pattern detection
        ├── Read/Glob/Grep → read_loop (3+ reads, no change)
        ├── Write/Edit → edit_revert (hash matches previous)
        └── Bash → test_fail_loop (3+ consecutive failures)
            │
            ▼
        Fire alert via stderr + log drift_detected metric
```

## Drift Alert

The #1 frustration with Claude Code isn't cost — it's wasted time.

Three patterns detected in real-time:

### Read Loop
Same file read 3+ times without a Write that changes its hash.
```
⚠️ Drift Alert: src/auth.ts read 4× without changes.
Claude may be stuck re-reading without progress.
→ Reframe the problem or /fae:checkpoint before /compact.
```

### Edit-Revert Cycle
File written, then written again to a hash matching a previous version.
```
⚠️ Drift Alert: src/auth.ts reverted to previous state 2×.
Claude is oscillating between approaches.
→ Pick one approach and commit to it.
```

### Test Fail Loop
Same base command fails 3+ times consecutively.
```
⚠️ Drift Alert: 'npm test' failed 4× this session.
Retrying without changes won't help.
→ Read the error, change the approach.
```

Alerts have a 5-turn cooldown to avoid noise.

## Token Estimation

Every tool call gets an estimated token count based on input + result byte sizes.
Logged as `{"event":"turn","tool":"Read","tokens_est":1200}` to metrics.jsonl.
This data powers `/fae:runway` and `/fae:analytics`.

## Performance

Fires on every tool call. Designed to be fast:
- `grep -c` for counting (no file loading)
- Pattern detection is O(1) per call
- Single `jq -s` on bounded `tail -n 20` for fail loop detection
- ~200-500 cache lines per session — trivial for grep

## Behavioral modules

Inherits the [shared behavioral modules](../../shared/) via root [CLAUDE.md](../../CLAUDE.md) — discipline, context, verification, delegation, failure-modes, tool-use, skill-authoring, hooks, precedent.
