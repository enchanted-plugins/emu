# context-guard

**The eyes of Allay.**

**Hook type:** PostToolUse — fires after every tool call.

## Drift Alert

The #1 frustration with Claude Code isn't cost — it's wasted time. "I spent 45 minutes before realizing Claude was going in circles."

context-guard detects three drift patterns in real-time:

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

## Commands

- `/allay:report` — Full session dashboard (Runway → Drift → Savings)
- `/allay:runway` — Quick turns-until-compaction check
- `/allay:doctor` — Diagnostic self-check for all plugins

## Performance

Fires on every tool call. Designed to be fast:
- `grep -c` for counting (no file loading)
- Pattern detection is O(1) per call
- ~200-500 cache lines per session — trivial for grep
