# context-guard

**The eyes of Allay.**

**Hook type:** PostToolUse — fires after every tool call.

## Components

| Type | Name | Description |
|------|------|-------------|
| Hook | detect-drift.sh | Drift detection + token estimation on every tool call |
| Skill | drift-awareness | Guides user out of unproductive loops |
| Skill | token-awareness | Runway monitoring and token efficiency advice |
| Command | /allay:report | Full session dashboard (Runway → Drift → Savings) |
| Command | /allay:runway | Quick turns-until-compaction check |
| Command | /allay:analytics | Per-tool token consumption breakdown |
| Command | /allay:doctor | Diagnostic self-check for all plugins |
| Agent | analyst | Background report generation (Haiku, forked) |

## Architecture

```
PostToolUse (Bash|Read|Write|Edit|MultiEdit|Glob|Grep)
    │
    ▼
detect-drift.sh
    │
    ├── Extract tool data (file path, hash, command, exit code)
    ├── Append to session cache (/tmp/allay-drift-*.jsonl)
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
→ Reframe the problem or /allay:checkpoint before /compact.
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
This data powers `/allay:runway` and `/allay:analytics`.

## Performance

Fires on every tool call. Designed to be fast:
- `grep -c` for counting (no file loading)
- Pattern detection is O(1) per call
- Single `jq -s` on bounded `tail -n 20` for fail loop detection
- ~200-500 cache lines per session — trivial for grep
