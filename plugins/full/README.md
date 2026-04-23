# full

**Meta-plugin. Installs every Emu plugin at once.**

This plugin has no hooks, skills, or agents of its own. It exists so you can install the whole 3-plugin platform with one command:

```
/plugin marketplace add enchanted-plugins/fae
/plugin install full@fae
```

Claude Code resolves the three dependencies and installs:

- `fae-context-guard` — drift alerts, runway forecast, per-tool analytics
- `fae-state-keeper` — checkpoint before compaction, auto-restore after
- `fae-token-saver` — compression, dedup, delta mode, output efficiency

If you want to cherry-pick a single plugin (e.g. just `fae-token-saver`), you can — but the three lifecycle phases (PreToolUse / PostToolUse / PreCompact) are designed to cooperate, so you'll typically want them all.

## Behavioral modules

Inherits the [shared behavioral modules](../../shared/) via root [CLAUDE.md](../../CLAUDE.md) — discipline, context, verification, delegation, failure-modes, tool-use, skill-authoring, hooks, precedent.
