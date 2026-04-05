# Allay
Open-source lightweight Claude Code plugin for token health, visibility, control, and proof.

**Every token accounted for.**

> 40 minutes into a session, Allay told me Claude had been
> editing and reverting the same file for 12 minutes.
> I didn't notice. It did.

## Drift Alert

Allay watches Claude's behavior across turns and catches
when it's going in circles:

- **Read loops** — same file read 3x without changes
- **Edit-revert cycles** — editing back to a previous version
- **Test fail loops** — same command failing repeatedly

When detected, you get a real-time alert before you waste
another 20 minutes on a stuck session.

## Token Runway

Not "43% context used." Not "$0.12 spent."
Just: **"~8 turns until compaction."**

## The Receipt

`/allay:report` shows exact savings per feature, drift alerts
fired, and turns remaining. Conservative methodology.
We don't inflate numbers.

## Install

Start with context-guard. It's the one you'll feel.

```
/plugin marketplace add allay-dev/allay
/plugin install context-guard@allay
```

Full suite:
```
/plugin install state-keeper@allay
/plugin install token-saver@allay
/plugin install context-guard@allay
```

Or manually:
```bash
bash <(curl -s https://raw.githubusercontent.com/allay-dev/allay/main/install.sh)
```

## 3 Plugins, 3 Hook Types, Zero Overlap

| Plugin | Hook | What |
|--------|------|------|
| state-keeper | PreCompact | Checkpoint before compaction |
| token-saver | PreToolUse | Compress output, block dupes |
| context-guard | PostToolUse | Drift Alert + Runway + Report |

Combined: 30-45% token reduction. Not 70%. Honest numbers.
Plus the only tool that catches Claude going in circles.

## vs Everything Else

| | Allay | Context Mode | Cozempic |
|---|---|---|---|
| Drift detection | real-time | - | - |
| Turn forecast | Runway | - | threshold only |
| Savings proof | /allay:report | ctx_stats | session report |
| Compaction survival | checkpoint.md | SQLite | team state |
| Dependencies | bash + jq | Node.js + MCP | Python |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
