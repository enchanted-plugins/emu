# token-saver

**Hook type:** PreToolUse + PostToolUse — fires before and after tool execution.

## Install

Part of the [Emu](../..) bundle. The simplest install is the `full` meta-plugin, which pulls in all 3 Emu plugins via dependency resolution:

```
/plugin marketplace add enchanted-plugins/fae
/plugin install full@fae
```

To install this plugin on its own: `/plugin install fae-token-saver@fae`. `token-saver`'s compression metrics feed `context-guard`'s savings report, and the tokens it reclaims extend the runway that `state-keeper` checkpoints defend across compactions — so on its own the wins are invisible and compactions stay uncheckpointed.

## Components

| Type | Name | Description |
|------|------|-------------|
| Hook | compress-bash.sh | Compresses verbose bash output (15 rules) |
| Hook | block-duplicates.sh | Blocks duplicate reads, delta mode for changes |
| Hook | age-results.sh | Alerts on aged tool results consuming context |
| Skill | compression-rules | Reference for all compression rules and bypass |
| Skill | output-efficiency | Terse mode instructions (off/lite/full/ultra) |
| Agent | compressor | Compression strategy analysis (Haiku, forked) |

## Architecture

```
PreToolUse (Bash)           PreToolUse (Read)          PostToolUse (all)
    │                           │                           │
    ▼                           ▼                           ▼
compress-bash.sh           block-duplicates.sh         age-results.sh
    │                           │                           │
    ├── Skip: FULL:,        ├── Sanitize path           ├── Count calls
    │   piped, interactive  ├── Compute hash            ├── Check age tier
    ├── Match 15 rules      ├── Check cache             └── Alert if old + large
    ├── Output updatedInput │   ├── Same hash → BLOCK       │
    └── Log metric          │   ├── Diff hash → DELTA       ▼
                            │   └── No cache → PASS     state/metrics.jsonl
                            └── Cache for next read
```

## Bash Compression (15 rules)

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

### Bypass

Prefix any command with `FULL:` to skip compression entirely.

## Duplicate Read Blocking + Delta Mode

1. **First read**: Pass through. Cache file hash + content copy.
2. **Re-read, same hash**: Block (exit 2). Show preview and elapsed time.
3. **Re-read, different hash**: Delta mode — show unified diff with ±3 context lines. Pass through.

Delta mode only activates when the diff is smaller than half the full file.

## Output Efficiency

Configurable terse mode that reduces output token waste:

| Mode | What it does |
|------|-------------|
| off | No output compression |
| lite | Remove filler phrases only |
| full | Terse mode — bullets, no summaries, lead with answers |
| ultra | Caveman mode — minimal prose, max compression |

Code blocks are never modified — only prose is compressed.

## Tool Result Aging

Tracks tool call count per session. For old results (30+ calls ago) that are large:
- Alerts via stderr that the result may be stale
- Logs `result_aged` event to metrics for analytics

## Behavioral modules

Inherits the [shared behavioral modules](../../shared/) via root [CLAUDE.md](../../CLAUDE.md) — discipline, context, verification, delegation, failure-modes, tool-use, skill-authoring, hooks, precedent.
