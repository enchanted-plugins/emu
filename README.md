# Allay

The context health platform that learns what wastes your tokens — and stops it.

**3 plugins. 2 agents. 15 compression rules. One install.**

> 40 minutes into a session, Allay told me Claude had been editing and reverting
> the same file for 12 minutes. I didn't notice. It did.

## How It Works

```
PreToolUse                    PostToolUse                   PreCompact
    │                             │                             │
    ▼                             ▼                             ▼
┌──────────┐              ┌──────────────┐             ┌──────────────┐
│token-saver│              │context-guard │             │ state-keeper │
│           │              │              │             │              │
│ compress  │──→ Bash  ──→│ drift detect │             │  checkpoint  │
│ dedup     │──→ Read  ──→│ token est.   │             │  before wipe │
│ delta     │              │ aging alerts │             │  auto-restore│
└──────────┘              └──────────────┘             └──────────────┘
    │                             │                             │
    ▼                             ▼                             ▼
 exit 0/2                    stderr alert                  checkpoint.md
 updatedInput                metrics.jsonl                 metrics.jsonl
```

Each plugin owns one hook lifecycle phase. No overlap. No dependencies between plugins.

## What Makes Allay Different

### Drift Alert

Catches Claude spinning in circles — in real time, not after the fact:

```
⚠️ Drift Alert: src/auth.ts read 4× without changes.
Claude may be stuck re-reading without progress.
→ Reframe the problem or /allay:checkpoint before /compact.
```

Three patterns: **read loops**, **edit-revert cycles**, **test fail loops**.
5-turn cooldown between alerts to avoid noise.

### Token Runway

Not "43% context used." Not "$0.12 spent."
Just: **"~8 turns until compaction."**

```
⚠️ RUNWAY: ~8 turns remaining | 4,200 tokens/turn avg
```

### Per-Tool Analytics

See exactly where your tokens go:

```
TOOL ANALYTICS (this session)
  Read:    42 calls, ~18,400 tokens (34%)
  Bash:    28 calls, ~14,200 tokens (26%)
  Write:   15 calls, ~11,800 tokens (22%)
```

### Output Efficiency

Configurable terse mode that cuts output token waste without losing information.
Four levels: off / lite / full / ultra. Code stays verbose — only prose gets lean.

### Delta Mode

Re-reading a changed file? Allay shows only what changed instead of the full file.
Re-reading an unchanged file? Blocked — with a preview and elapsed time.

### The Receipt

`/allay:report` shows exact savings per feature, drift alerts fired, and turns
remaining. Conservative methodology. We don't inflate numbers.

## Install

```
/plugin marketplace add enchanted-plugins/allay
```

Start with context-guard. It's the one you'll feel:

```
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
bash <(curl -s https://raw.githubusercontent.com/enchanted-plugins/allay/main/install.sh)
```

## 3 Plugins, 2 Agents, 15 Compression Rules

| Plugin | Hook | Command | What |
|--------|------|---------|------|
| state-keeper | PreCompact | `/allay:checkpoint` | Checkpoint before compaction, auto-restore after |
| token-saver | PreToolUse | — | Compress output, block dupes, delta mode, output efficiency |
| context-guard | PostToolUse | `/allay:report` | Drift Alert + Runway + Analytics + Report |

| Agent | Model | Plugin | What |
|-------|-------|--------|------|
| analyst | Haiku | context-guard | Background report generation |
| restorer | Haiku | state-keeper | Autonomous context restoration |

## What You Get Per Session

```
state-keeper/state/
├── checkpoint.md        # Pre-compaction snapshot (branch, files, instructions)
├── remember.md          # User-flagged context (/allay:checkpoint items)
└── metrics.jsonl        # checkpoint_saved events

token-saver/state/
└── metrics.jsonl        # bash_compressed, duplicate_blocked, delta_read events

context-guard/state/
└── metrics.jsonl        # turn (token est.), drift_detected events
```

## Commands

| Command | Plugin | What |
|---------|--------|------|
| `/allay:report` | context-guard | Full session dashboard (Runway → Drift → Savings) |
| `/allay:runway` | context-guard | Quick turns-until-compaction check |
| `/allay:analytics` | context-guard | Per-tool token consumption breakdown |
| `/allay:doctor` | context-guard | Diagnostic self-check for all plugins |
| `/allay:checkpoint [text]` | state-keeper | Save context that survives compaction |
| `/allay:checkpoint-show` | state-keeper | Display most recent automatic checkpoint |

## Compression Rules (15)

| Pattern | Action |
|---------|--------|
| npm/yarn/pnpm test, vitest, jest | `tail -n 40` |
| pytest, python -m unittest | filter pass/fail summary |
| go test | filter PASS/FAIL lines |
| mvn/gradle test | filter BUILD + test summary |
| dotnet build/test | filter pass/fail summary |
| npm/yarn/pnpm install | filter errors/warnings |
| cargo build/test | filter errors/warnings |
| make | filter errors or "Build succeeded" |
| docker build | filter layer summaries + image ID |
| terraform plan | filter Plan summary |
| eslint | filter error count + first errors |
| tsc | filter TS errors |
| git log (verbose) | `--oneline -20` |
| find (no head) | `head -n 30` |
| cat (>100 lines) | `head -n 80` + line count |

Bypass: prefix with `FULL:` to skip compression.

## vs Everything Else

| | Allay | Caveman | Cozempic | context-mode | token-optimizer |
|---|---|---|---|---|---|
| Drift detection | real-time, 3 patterns | — | — | — | — |
| Turn forecast | Runway | — | threshold only | — | — |
| Output reduction | 4 modes | 65% prose cut | — | — | — |
| Input compression | 15 rules | — | 18 strategies | — | — |
| Delta mode | diff on re-read | — | — | — | delta mode |
| Per-tool analytics | /allay:analytics | — | — | per-tool stats | waste dashboard |
| Tool result aging | age-based alerts | — | 3-tier stubbing | — | — |
| Savings proof | /allay:report | — | session report | ctx_stats | quality score |
| Compaction survival | checkpoint.md | — | team state | SQLite | checkpoints |
| Agents | 2 (Haiku) | — | — | — | — |
| Dependencies | bash + jq | — | Python | Node.js + MCP | Node.js |

Combined: 30-45% token reduction. Not 70%. Honest numbers.
Plus the only tool that catches Claude going in circles.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
