# Contributing to Allay

## Stack

bash + jq only. No Node.js. No Python. No external APIs.

## Critical Rules

Before submitting a PR, verify:

1. **Never use `flock`** — macOS doesn't have it. Use atomic `mkdir` for locks.
2. **Never use `$CLAUDE_SESSION_ID`** for cache keys — doesn't reset after /clear.
3. **Never use `jq -s`** on growing files — slurps entire file into RAM.
4. **Every hook has `trap 'exit 0' ERR INT TERM`** — hooks must never break Claude.
5. **64KB stdout limit** — write large output to tmpfiles.
6. **Validate JSON before parsing** with `jq empty`.
7. **Block URL-encoded path traversal** — decode `%2e%2e` before checking.
8. **Rotation at 10MB** not 1MB.

## Testing

```bash
bash tests/run-all.sh
```

Each test pipes mock JSON to hooks via stdin and verifies exit codes and output.

## Architecture

Each plugin owns exactly one hook lifecycle phase:
- state-keeper → PreCompact
- token-saver → PreToolUse
- context-guard → PostToolUse

No plugin depends on another. All plugins write to their own `state/metrics.jsonl`.

## Shared Code

`shared/` contains utilities sourced by all hooks. Hooks resolve the path via:
```bash
SHARED_DIR="${PLUGIN_ROOT}/../../shared"
```

## Submitting

1. `shellcheck -x` passes on all `.sh` files
2. `tests/run-all.sh` exits 0
3. No banned patterns (`flock`, `jq -s`, `$CLAUDE_SESSION_ID` as cache key)
