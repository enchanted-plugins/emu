# The Science Behind Allay

Formal mathematical models powering every context-health engine in Allay.

These aren't abstractions. Every formula maps to running code.

---

## A1. Markov Drift Detection

**Problem:** Detect when a session enters unproductive loops — reading the same file without changes, repeatedly failing the same command, or oscillating between edit and revert.

<p align="center"><img src="../assets/math/a1-drift.svg" alt="P(drift | s_1, ..., s_n) = 1 if |{ s_i = s_j }| >= theta, else 0"></p>

The `detect-drift.sh` hook (PostToolUse) maintains a JSONL ring of the last 20 tool calls. Three drift patterns fire: read-loop (same file ≥ 3× without an intervening hash-changing write), edit-revert (current write-hash matches a historical hash for the same file), and test-fail-loop (same command fails ≥ 3× consecutively). Alerts emit on stderr with a 5-turn cooldown to avoid alert fatigue. Pattern frequencies accumulate via EMA (α = 0.3) in `learnings.json`.

**Implementation:** `plugins/context-guard/hooks/post-tool-use/detect-drift.sh`, `shared/scripts/learnings.sh`

---

## A2. Linear Runway Forecasting

**Problem:** Estimate how many tool calls remain before the token budget is exhausted, given the current burn rate.

<p align="center"><img src="../assets/math/a2-runway.svg" alt="R_hat = (C_max - sum t_i) / avg_t; CI_95 = R_hat +/- 1.96 * sigma_t / avg_t * R_hat"></p>

Tokens per call are approximated from the summed byte size of `tool_input + tool_result` multiplied by 0.325 tokens/char (≈ 1.3 tokens/word at 4 chars/word), with a floor of 50 tokens to absorb overhead. `report-gen.sh` reads the last 5 turn events from `metrics.jsonl`, computes a rolling average, and divides the remaining budget (200,000 − spent). A warning fires when `runway_turns < 10`. The 95% confidence interval widens as turn-to-turn variance grows.

**Implementation:** `plugins/context-guard/hooks/post-tool-use/detect-drift.sh`, `shared/scripts/report-gen.sh`

---

## A3. Shannon Compression (Language-Aware Output Minification)

**Problem:** Verbose tool outputs (test logs, build logs, install summaries) are mostly noise; tokens wasted on them crowd out useful context.

<p align="center"><img src="../assets/math/a3-shannon.svg" alt="H(O') >= theta * H(O); theta = 1.0 for code, 0.7 for tests, 0.3 for logs"></p>

The `compress-bash.sh` hook (PreToolUse on Bash) pattern-matches against 15 known verbose command families — npm/yarn/pnpm test, pytest, go test, Maven, Gradle, dotnet, Cargo, make, docker build, terraform plan, eslint, tsc, git log, find, cat. For each match it rewrites the command to pipe through a `grep` / `tail` filter preserving only signal lines (pass/fail, error counts, build status). Example: `npm test` → `npm test 2>&1 | tail -n 40`. The compression bound guarantees signal entropy stays above θ of the original — code is preserved (θ = 1.0), tests mostly kept (θ = 0.7), logs aggressively trimmed (θ = 0.3).

**Implementation:** `plugins/token-saver/hooks/pre-tool-use/compress-bash.sh`, `shared/scripts/learnings.sh`

---

## A4. Atomic State Serialization (Checkpoint Protocol)

**Problem:** Preserve session context (git state, project instructions, user-flagged notes) before compaction wipes the transcript, so the session can resume with full context.

<p align="center"><img src="../assets/math/a4-atomic.svg" alt="write(tmp) -> validate(tmp) -> rename(tmp, target)"></p>

The `save-checkpoint.sh` hook (PreCompact) collects: current branch (`git branch --show-current`), modified files (`git diff --name-only HEAD`), staged files (`git diff --cached --name-only`), recent commits (`git log --oneline -10`), CLAUDE.md (first 50 lines), and user-flagged `state/remember.md`. Sections concatenate into a markdown buffer; over 50 KB triggers truncation. Writing is atomic: temp file → validate → `rename` under an `mkdir`-based lock. On session resume, the restorer agent reads `checkpoint.md` to reconstruct context.

**Implementation:** `plugins/state-keeper/hooks/pre-compact/save-checkpoint.sh`

---

## A5. Content-Addressable Dedup (Duplicate Read Blocking)

**Problem:** Re-reading the same unchanged file within a session wastes tokens and signals a read loop.

<p align="center"><img src="../assets/math/a5-dedup.svg" alt="decision(f) = BLOCK if h(f) == h_cached AND delta_t < TTL; ALLOW if delta_t >= TTL"></p>

<p align="center"><img src="../assets/math/a6-delta.svg" alt="decision(f) = DELTA when h(f) != h_cached AND delta_t < TTL"></p>

The `block-duplicates.sh` hook (PreToolUse on Read) maintains a session-scoped cache `/tmp/allay-reads-<session>.jsonl`. Each Read: hash the target file, look up the most recent cache entry for the same path. Same hash within the 10-minute TTL → block with exit 2, return a preview and suggest the `FULL:` bypass prefix. Hash differs → emit a unified diff as delta if the diff is under half the file size; otherwise let the read proceed and refresh the cache.

**Implementation:** `plugins/token-saver/hooks/pre-tool-use/block-duplicates.sh`

---

## A6. Delta-Read Telemetry

**Problem:** Track when a file is re-read after modification within a TTL window, logging telemetry to detect re-read patterns.

The `block-duplicates.sh` hook emits `delta_read` events when a file's hash changes and the file is accessed again within the TTL (600s). Each event records file path, full line count, and diff line count for later pattern analysis.

**Implementation:** `plugins/token-saver/hooks/pre-tool-use/block-duplicates.sh`, `shared/scripts/learnings.sh`

## Derivation (TODO — Phase 2)

---

## A7. Exponential Strategy Averaging

**Problem:** Accumulate compression strategy success rates and drift frequencies across sessions using exponential moving average.

Uses EMA with α=0.3 to blend current-session metrics into historical rates. Tracks success of individual compression rules (test_tail, pytest_filter, etc.) and drift pattern frequencies (read_loop, edit_revert, test_fail_loop). Detects dormant rules and chronic patterns for adaptive compression in future sessions.

**Implementation:** `shared/scripts/learnings.sh`

## Derivation (TODO — Phase 2)

---

## A8. Skill-Scoped Attribution

**Problem:** Attribute every tool call to the skill that invoked it, enabling per-skill token analytics and cost allocation.

Every tool call is attributed to the currently-active skill via a LIFO stack. Skills register scope at entry with a 16-hex-char invocation ID (surviving PID reuse per systemd convention). Attributes persist to `skill-metrics.jsonl` alongside `metrics.jsonl`. Emitted independently of standard metrics for fine-grained per-skill breakdown via `/allay:analytics`.

**Implementation:** `plugins/context-guard/hooks/post-tool-use/detect-drift.sh`, `shared/scripts/session-init.sh`

## Derivation (TODO — Phase 2)

---

## A9. Worktree Session Graph

**Problem:** Unify token accounting across multiple git worktrees of the same repository into one cross-worktree view.

Derives a stable repository ID from the first commit hash (git rev-list --max-parents=0 HEAD) to identify the repo across all clones, forks, and worktrees. Sessions write to global state directories keyed by repo_id, with per-PID sharding to avoid concurrent-append interleaving. Readers glob + merge shards, then emit a WORKTREE OVERVIEW in `/allay:report` when ≥2 worktrees are detected.

**Implementation:** `shared/scripts/session-init.sh`, `plugins/context-guard/agents/analyst.md`

## Derivation (TODO — Phase 2)

---

*Every formula maps to executable code in the enchanted-plugins ecosystem. The math runs.*
