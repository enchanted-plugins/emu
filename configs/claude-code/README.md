# Claude Code Configuration

This directory contains example Claude Code configuration snippets for use with Emu.

## Installing Plugins

After cloning the Emu repo, add plugins to Claude Code:

```bash
# Add the marketplace (recommended)
/plugin marketplace add /path/to/fae

# Or add individual plugins
/plugin add /path/to/fae/plugins/context-guard
/plugin add /path/to/fae/plugins/state-keeper
/plugin add /path/to/fae/plugins/token-saver
```

## Recommended Order

1. **context-guard** — Install first. Drift Alert and Runway are immediately useful.
2. **state-keeper** — Install if you hit compactions often.
3. **token-saver** — Install for long sessions where token savings compound.
