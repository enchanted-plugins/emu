# Changelog

All notable changes to `emu` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/enchanted-plugins/emu/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/enchanted-plugins/emu/releases/tag/v2.0.0
