# Emu — Agent Contract

Audience: Claude. Emu watches context health — compresses tool output, detects drift, forecasts runway, checkpoints before compaction.

## Shared behavioral modules

These apply to every skill in every plugin. Load once; do not re-derive.

- @shared/conduct/discipline.md — coding conduct: think-first, simplicity, surgical edits, goal-driven loops
- @shared/conduct/context.md — attention-budget hygiene, U-curve placement, checkpoint protocol
- @shared/conduct/verification.md — independent checks, baseline snapshots, dry-run for destructive ops
- @shared/conduct/delegation.md — subagent contracts, tool whitelisting, parallel vs. serial rules
- @shared/conduct/failure-modes.md — 14-code taxonomy for accumulated-learning logs
- @shared/conduct/tool-use.md — tool-choice hygiene, error payload contract, parallel-dispatch rules
- @shared/conduct/skill-authoring.md — SKILL.md frontmatter discipline, discovery test
- @shared/conduct/hooks.md — advisory-only hooks, injection over denial, fail-open
- @shared/conduct/precedent.md — log self-observed failures to `state/precedent-log.md`; consult before risky steps

When a module conflicts with a plugin-local instruction, the plugin wins — but log the override.

## Lifecycle

| Plugin | Hook | Purpose |
|--------|------|---------|
| token-saver | PreToolUse (Bash) | Compress verbose output (A3) |
| token-saver | PreToolUse (Read) | Block duplicate reads, return delta (A5, A6) |
| token-saver | PostToolUse | Age old tool results |
| context-guard | PostToolUse | Estimate tokens, detect drift (A1, A2) |
| state-keeper | PreCompact | Write atomic checkpoint (A4) |

See `./plugins/<name>/hooks/hooks.json` for matchers. Agents in `./plugins/<name>/agents/`.

## Algorithms

A1 Markov Drift Detection · A2 Linear Runway Forecasting · A3 Shannon Compression · A4 Atomic State Serialization · A5 Content-Addressable Dedup · A6 Delta-Read Telemetry · A7 Exponential Strategy Averaging. Derivations in `README.md` § *The Science Behind Emu*.

## Behavioral contracts

Markers: **[H]** hook-enforced (deterministic) · **[A]** advisory (relies on your adherence).

1. **[H] IMPORTANT — Respect the delta.** When token-saver returns a unified diff instead of full file contents, work from the diff. Do not re-invoke Read to get the full file; the block was intentional (A5/A6).
2. **[H] Respect duplicate blocks.** If a Read is blocked as duplicate, use your prior read. Do not obfuscate the path to bypass the TTL.
3. **[A] YOU MUST acknowledge `[Emu]` stderr.** Name the pattern (read loop / edit-revert / fail loop) or the runway alert, then change approach. Silence after a drift alert is a contract violation.
4. **[A] Checkpoint when runway < 8.** Offer `/fae:checkpoint <short note>` with the current sub-task state before compaction eats the context.
5. **[A] Honest numbers.** When producing `/fae:report`, surface only what `metrics.jsonl` contains. Never infer, smooth, or round up savings.
6. **[A] ESCALATE on stale metrics.** If `metrics.jsonl` is empty or malformed, report "no data" — do not fabricate a report shell.
7. **[A] ESCALATE on conflicting drift + runway.** If the session shows drift AND runway < 5, pause and summarize both before the developer loses context.

## Response tables

### Drift patterns (A1)
| Pattern | Trigger | Action |
|---------|---------|--------|
| READ_LOOP | same file read ≥ 3× without edits | Reframe the problem; stop re-reading |
| EDIT_REVERT | file edited then reverted to prior hash | Step back; the fix is not landing |
| TEST_FAIL_LOOP | same test fails ≥ 3× | Change approach; do not re-run |

5-turn cooldown. Thresholds: `FAE_DRIFT_READ_THRESHOLD`, `FAE_DRIFT_FAIL_THRESHOLD`.

### Runway (A2)
| Runway | Confidence source | Action |
|--------|-------------------|--------|
| > 20 turns | velocity window stable | Work normally |
| 8–20 turns | — | Wrap current sub-task cleanly |
| < 8 turns | — | Run `/fae:checkpoint` before continuing |

## State paths

```
plugins/token-saver/state/metrics.jsonl       (append-only)
plugins/context-guard/state/metrics.jsonl     (append-only)
plugins/context-guard/state/learnings.json    (mutable, A7 EMA)
plugins/state-keeper/state/checkpoint.md      (mutable, atomic rename)
plugins/state-keeper/state/remember.md        (mutable, user-flagged)
```

Never write these paths directly — they're owned by hooks and agents.

## Agent tiers

All 4 agents are Haiku (validator tier — Orchestrator/Opus, Executor/Sonnet, Validator/Haiku is the @enchanted-plugins convention): `analyst`, `forecaster`, `compressor`, `restorer`. Each has an explicit output contract in its `agents/*.md`.

## Terse output modes

Emu ships an output-efficiency skill: `off`, `lite`, `full`, `ultra`. Match your response style to the current mode. `ultra` → drop narration. Code stays verbose regardless.

## Anti-patterns

- **Prefix bypass.** Using `FULL:` to dodge A3 compression when the developer did not request raw output. The bypass exists for rare debugging, not default behavior.
- **Silent savings inflation.** Reporting `/fae:report` totals that don't match `metrics.jsonl` line counts. Breaks the honest-numbers contract, which is the product.
- **Checkpoint drift.** Writing to `checkpoint.md` outside the PreCompact hook. The atomic rename protocol (A4) is the only safe write path.
- **Drift-alert hand-wave.** Acknowledging the alert then continuing the same action. The cooldown exists so repeated alerts mean something.
