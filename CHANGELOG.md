# Changelog

All notable changes to `emu` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.1] — VF-04 session-cache fix, honest auto-restore scoping

_Notes author: Enchanter Labs._

First release cut against the post-VF-04 working state on `main`. The `3.0.0`
tag captured only the rename/docs commit; the session-cache fix and the
`foundations → vis` bootstrap re-wiring that followed it had never shipped in a
tagged release. This closes that gap.

### Fixed
- **VF-04 — session-scoped caches were reborn empty every turn.** The hooks
  keyed their per-session cache off an MD5 of the transcript file _contents_.
  The transcript grows every turn, so the key changed on every invocation and
  every session-scoped cache (drift detection, dedup, result-aging, checkpoint)
  started from scratch each call — silently defeating drift cooldowns, duplicate
  blocking, and continuity. The hooks now key off the stable `session_id` from
  the hook payload. Fix spans all three code plugins:
  `context-guard/hooks/post-tool-use/detect-drift.sh`,
  `state-keeper/hooks/pre-compact/save-checkpoint.sh`,
  `token-saver/hooks/post-tool-use/age-results.sh`, and
  `token-saver/hooks/pre-tool-use/block-duplicates.sh`.

### Changed
- Bootstrap re-wired against the renamed `vis` shared substrate (was
  `foundations`), with F22–F28 + metacognition conduct modules and a
  deterministic (`LC_ALL=C`) `.vis-lock` order. `scripts/bootstrap.sh --verify`
  is green (20 conduct files, 3 packages).
- Honest wording for state-keeper's restore capability in both the plugin
  manifest and the marketplace entry — see "Known limitations" below.

### Current capabilities (verified this release)
- **token-saver** (`PreToolUse`): output compression, duplicate-read blocking,
  delta-on-reread, output-efficiency instructions.
- **context-guard** (`PostToolUse`): Markov drift detection (READ_LOOP /
  EDIT_REVERT / TEST_FAIL_LOOP with cooldown), linear runway forecasting,
  per-tool token analytics, savings report.
- **state-keeper** (`PreCompact`): atomic pre-compaction checkpoint of branch,
  modified/staged files, recent commits, and flagged context.
- Honest-numbers contract: advisories cite the observed pattern, not inferred
  intent.

### Known limitations / follow-up
- **Auto-restore is not yet deterministically wired — slated for re-scoping.**
  state-keeper reliably _saves_ a checkpoint on `PreCompact`, but the "auto-restore
  after compaction" claim is aspirational: there is no `SessionStart` /
  post-compact hook that guarantees the restorer runs. Restoration today depends
  on the `emu-restorer` agent or the `state-recovery` skill being invoked
  (model-discretionary), or the manual `/emu:checkpoint-show` command. The save
  path is production-ready; the automatic restore path is deferred to a future
  release for a proper re-scope (likely a `SessionStart` hook). Descriptions
  have been updated to stop overclaiming until then.

## [3.0.0] — rename: emu identity, standardized origin format

### Added
- Tier-1 governance docs: `SECURITY.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`, `PRIVACY.md`.
- `.github/` scaffold: issue templates, PR template, CODEOWNERS, dependabot config.
- Tier-2 docs: `docs/getting-started.md`, `docs/installation.md`, `docs/troubleshooting.md`, `docs/performance.md`, `docs/adr/README.md`.

## [2.0.0] — session companion, honest-numbers contract

The current shipped release. See [README.md](README.md) for the complete feature surface.

### Highlights
- 3 plugins spanning the session-health lifecycle.
- 9 named algorithms (Markov, Runway, Shannon, Atomic, Dedup, among others) — formal derivations in [docs/science/README.md](docs/science/README.md).
- 4 managed agents across the three ecosystem tiers.
- Token-saver and context-guard hooks: compress output, detect drift, block duplicate work.
- State-keeper checkpoint hook — save continuity before compaction.
- Honest-numbers contract: Emu reports what it actually observed, not what would look good in a demo.

[Unreleased]: https://github.com/enchanter-ai/emu/compare/v3.0.1...HEAD
[3.0.1]: https://github.com/enchanter-ai/emu/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/enchanter-ai/emu/releases/tag/v3.0.0
[2.0.0]: https://github.com/enchanter-ai/emu/releases/tag/v2.0.0
