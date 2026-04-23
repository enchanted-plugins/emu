# Performance

How much does Emu save, actually? This page is the skeleton for the answer. Numbers land here once benchmarks are wired into CI. Until then, the page states the **methodology** so any claim can be reproduced.

## What Emu is supposed to save

Three separate kinds of savings, each measured differently.

| Saving | Mechanism | Expected win |
|--------|-----------|--------------|
| **Runway extension** | `context-guard` compresses large tool outputs before they land in the window. | More turns per session before compaction / context reset. |
| **Dedup** | Identical re-reads of the same file or identical tool outputs are collapsed. | Fewer tokens spent on repeated evidence. |
| **Drift early-exit** | When Shannon entropy flags a drifting session, Emu emits an advisory so the user can abort early. | Spend avoided on sessions that were going nowhere. |

Savings are measured **per session**, not in aggregate, because session shape varies wildly (chat vs. code edit vs. long research).

## Methodology

### Workloads

Three canonical workloads, each deterministic:

1. **Edit loop** — 20 turns of fix-build-test against a small repo. Claude Code + one file, tight scope.
2. **Research** — 10 turns of "grep around, read a few files, summarize."
3. **Mixed** — 40 turns alternating edits and research, with 2 drift events injected.

Each workload has a fixed prompt script. Runs are deterministic modulo model non-determinism.

### Metrics

For each workload, measure both with-Emu and without-Emu:

| Metric | How it's measured |
|--------|-------------------|
| Total tokens (in + out) | Sum of Claude Code's own token counters across the run. |
| Turn count before compaction | Number of turns until the window triggers compaction / reset. |
| Tool-output bytes absorbed by context | Size of each tool-call payload, summed. |
| Dedup events | Count of turns where `context-guard` collapsed a duplicate. |
| Drift advisories | Count of turns where drift score crossed the threshold. |

### Reporting

Each benchmark run produces a JSON record with all metrics, workload id, Emu version, Claude Code version, model, and date. CI keeps the last 30 runs; this page links to the dashboard once wired.

### Honest-numbers contract

The benchmark may **not** cherry-pick. Published numbers come from the median run of the last 10 CI runs. Single best-case numbers do not ship on this page. See the root `CLAUDE.md` honest-numbers contract.

## Reproducing locally

```bash
# clone and install
git clone https://github.com/enchanted-plugins/fae.git
cd fae
bash install.sh

# run the benchmark harness against each workload
bash tests/perf/run.sh edit-loop
bash tests/perf/run.sh research
bash tests/perf/run.sh mixed
```

Each run emits `tests/perf/results/<workload>-<timestamp>.json`. Compare across runs to see the distribution.

## Limits of these benchmarks

- **Model non-determinism.** Two identical prompt streams can produce different tool-call shapes. Benchmarks report median of N runs.
- **Workloads are not your workload.** The scripted workloads are intentionally generic. Your real savings depend on how large your tool outputs are and how often you re-read.
- **Savings require the plugin to actually fire.** A misconfigured hook (see [troubleshooting.md](troubleshooting.md)) quietly turns savings off. The `/doctor` command verifies the plugin is active.

## Expected results

Until CI numbers land here, **we make no numerical claims.** Anecdotes from our own sessions are not evidence — reproducible benchmarks are. If this section still says "TBD" when you read it, the benchmark harness hasn't landed; treat Emu as a best-effort savings layer.

## Related

- [PRIVACY.md](../PRIVACY.md) — what Emu reads and stores.
- [docs/science/README.md](science/README.md) — the algorithms that produce these savings, derived.
- [docs/glossary.md](glossary.md) — defines "runway", "drift", "dedup" in Emu's precise senses.
