# Allay — What You Need To Know

You have Allay installed. It watches your context budget, detects when you're spinning in circles, and preserves state before compaction so work survives.

## What's happening behind the scenes

Every time you use a tool:
1. **token-saver** (PreToolUse) compresses verbose commands, blocks duplicate reads, and returns diffs on re-reads (A3, A5, A6)
2. **context-guard** (PostToolUse) estimates tokens per turn, detects drift patterns, and forecasts runway (A1, A2)

Before compaction:
3. **state-keeper** (PreCompact) writes an atomic checkpoint so context survives the wipe (A4)

Across sessions:
4. **Bayesian Strategy Accumulation** (A7) updates `learnings.json` with what worked — dormant rules, chronic drift, velocity drift.

## Drift patterns — what they mean

| Pattern | Meaning | Your action |
|---------|---------|-------------|
| READ_LOOP | Same file read 3+ times without edits | Reframe the problem — you're stuck re-reading |
| EDIT_REVERT | File edited then reverted within a short window | Step back; the fix isn't working |
| TEST_FAIL_LOOP | Same test failing repeatedly | Change approach, don't retry the same fix |

5-turn cooldown between alerts. Thresholds via `ALLAY_DRIFT_*` env vars.

## Runway forecast — what it means

| Runway | Meaning | Your action |
|--------|---------|-------------|
| > 20 turns | Plenty of headroom | Work normally |
| 8–20 turns | Getting tight | Wrap up the current sub-task cleanly |
| < 8 turns | Near compaction | Run `/allay:checkpoint` with key context before continuing |

Confidence label (HIGH/MEDIUM/LOW) comes from coefficient of variation over the sliding window.

## What you MUST do

1. **When you see `[Allay]` drift alert in stderr**: Acknowledge it. Name the pattern (read loop / edit-revert / fail loop) and change approach. Don't keep doing the thing that triggered it.

2. **When runway drops below 8 turns**: Tell the developer. Offer to save a checkpoint via `/allay:checkpoint` with a short note of current state before the context wipes.

3. **When token-saver returns a delta instead of full file contents**: Use the diff — don't demand the full file. That's the whole point of A6.

4. **When a duplicate read is blocked**: Don't retry with a different approach to bypass it. The file is unchanged; use what you already read.

5. **After compaction / session restore**: Read `plugins/state-keeper/state/checkpoint.md` and `plugins/state-keeper/state/remember.md`. Brief the developer on what was happening before the wipe.

6. **When the developer asks "where did my tokens go"**: Read `plugins/token-saver/state/metrics.jsonl` and `plugins/context-guard/state/metrics.jsonl`. Give a per-tool breakdown, not a file dump.

## Commands the developer can use

- `/allay:report` — full session dashboard (runway → drift → savings → learnings)
- `/allay:runway` — quick turns-until-compaction estimate with 95% CI
- `/allay:analytics` — per-tool token consumption breakdown
- `/allay:checkpoint [text]` — save user-flagged context that survives compaction
- `/allay:checkpoint-show` — display the most recent automatic checkpoint
- `/allay:doctor` — diagnostic self-check for all plugins

## Terse output modes

Allay has four output modes: `off`, `lite`, `full`, `ultra`. Code stays verbose — only prose gets lean. Match your response style to the current mode. If the developer sets `ultra`, drop the narration.

## What NOT to do

- Don't suppress or dismiss drift alerts — they exist because you were doing the thing
- Don't modify Allay state files (metrics.jsonl, learnings.json, checkpoint.md)
- Don't re-read a file token-saver already returned — use the delta or cached copy
- Don't prefix commands with `FULL:` to bypass compression unless the developer asked for raw output
- Don't inflate the savings numbers in `/allay:report` — Allay's honest-numbers contract is the whole point
