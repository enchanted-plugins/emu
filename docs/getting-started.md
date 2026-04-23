# Getting started with Emu

Emu is the session companion: it watches your context window, tracks token spend, catches drift before it becomes a compaction, and saves a checkpoint so you can resume after a restart. This page gets you from zero to a live runway readout in under 5 minutes.

## 1. Install (60 seconds)

```
/plugin marketplace add enchanted-plugins/fae
/plugin install full@fae
/plugin list
```

You should see the Emu sub-plugins including `context-guard` and `state-keeper`. If any are missing, see [installation.md](installation.md).

## 2. Check your runway

Start a Claude Code session and run:

```
/runway
```

This shows:

- **Tokens used** — live count against your model's window.
- **Runway** — estimated turns remaining at the current burn rate.
- **Drift signal** — Shannon entropy of recent turns, flagged if the session is veering off-topic.

Emu uses the **Runway** algorithm — exponentially-weighted moving average over recent turn sizes — so the estimate adapts when you switch from a heavy brainstorm to a tight edit loop.

## 3. Let drift detection run passively

As you work, Emu's `context-guard` hook fires on every post-tool event. It:

- Compresses large tool outputs that would otherwise pollute the window.
- Blocks duplicate work — if you've already `Read` the same file this turn, the hook reminds you.
- Emits a drift warning when topic entropy crosses a threshold.

No configuration needed — the defaults land you inside the honest-numbers contract: Emu reports what it observed, not what would look good.

## 4. Checkpoint before compaction

When the context window gets tight, save a checkpoint:

```
/checkpoint
```

`state-keeper` writes the session's goal, open decisions, and next step to `~/.claude/fae/checkpoints/`. After `/clear` or a restart:

```
/checkpoint-show
```

restores the context as a source-of-truth block — no re-reading old turns.

## 5. Diagnostics

```
/doctor
```

Runs Emu's self-check: hooks registered, jq available, Python scripts reachable, state dir writable. If anything fails, see [troubleshooting.md](troubleshooting.md).

## Reports

```
/report           Session summary — tokens, turns, drift events, top-3 token sinks.
/analytics        Rolling stats across recent sessions.
```

## Next steps

- [performance.md](performance.md) — token-savings benchmarks and how to reproduce them.
- [PRIVACY.md](../PRIVACY.md) — exactly what Emu reads, stores, and transmits (spoiler: nothing leaves your machine).
- [docs/science/README.md](science/README.md) — Markov, Runway, Shannon, Atomic, Dedup, derived.
- [docs/architecture/](architecture/) — auto-generated diagram.

Broken first run? → [troubleshooting.md](troubleshooting.md).
