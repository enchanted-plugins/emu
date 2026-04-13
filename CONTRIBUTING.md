# Contributing to Allay

## Stack

bash + jq only for hooks. No Node.js. No Python. No external APIs.
Python stdlib is OK for non-time-critical scripts (report generation).

## Critical Rules

Before submitting a PR, verify:

1. **Never use `flock`** — macOS doesn't have it. Use atomic `mkdir` for locks.
2. **Never use `$CLAUDE_SESSION_ID`** for cache keys — doesn't reset after /clear.
3. **Never use `jq -s`** on growing files — slurps entire file into RAM. Safe on bounded inputs (`tail -n 20` output).
4. **Every hook has `trap 'exit 0' ERR INT TERM`** — hooks must never break Claude.
5. **64KB stdout limit** — write large output to tmpfiles under `/tmp/allay-*`.
6. **Validate JSON before parsing** with `jq empty`.
7. **Block URL-encoded path traversal** — decode `%2e%2e` before checking.
8. **Rotation at 10MB** not 1MB.
9. **Use `jq -n --arg`** for JSON construction — never printf/sed chains.

## Code Style

- `shellcheck -x` passes on all `.sh` files
- Use `printf "%s"` over `echo` for variable content
- Use `local` for function variables
- Quote all variable expansions (`"$var"` not `$var`)
- Use `[[ ]]` over `[ ]` for conditionals
- Use `$(command)` over backticks
- Keep hook scripts under 200 lines
- One responsibility per hook script

## Testing

```bash
bash tests/run-all.sh
```

Each test pipes mock JSON to hooks via stdin and verifies exit codes and output.
Tests must clean up all temp files and state files after running.

## Architecture

Each plugin owns exactly one hook lifecycle phase:

```
PreToolUse   →  token-saver     (compress, dedup, delta)
PostToolUse  →  context-guard   (drift detect, token estimation, aging alerts)
PreCompact   →  state-keeper    (checkpoint, restore)
```

No plugin depends on another. All plugins write to their own `state/metrics.jsonl`.

## Adding a Plugin

Create the following structure:

```
plugins/<name>/
├── .claude-plugin/plugin.json      # name, description, version, author, license, keywords, skills, agents
├── skills/<skill>/SKILL.md         # allowed-tools frontmatter, instructions
├── agents/<agent>.md               # model, context: fork, allowed-tools, instructions
├── commands/<command>.md            # slash commands
├── hooks/
│   ├── hooks.json                  # lifecycle bindings
│   └── <hook-point>/<script>.sh    # hook scripts
├── state/.gitkeep                  # runtime state
└── README.md                       # plugin-level documentation
```

Register the plugin in `.claude-plugin/marketplace.json`.

### plugin.json template

```json
{
  "name": "allay-<plugin-name>",
  "description": "<one-line description>",
  "version": "2.0.0",
  "author": { "name": "Allay" },
  "license": "MIT",
  "keywords": ["<relevant>", "<keywords>"],
  "commands": ["./commands/<cmd>.md"],
  "skills": ["./skills/<skill>/"],
  "agents": "./agents/"
}
```

## Adding a Hook

1. Create the script in `plugins/<plugin>/hooks/<hook-point>/<name>.sh`
2. Add the binding in `plugins/<plugin>/hooks/hooks.json`
3. Start with:
   ```bash
   #!/usr/bin/env bash
   trap 'exit 0' ERR INT TERM
   set -uo pipefail
   ```
4. Source shared utilities:
   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
   SHARED_DIR="${PLUGIN_ROOT}/../../shared"
   source "${SHARED_DIR}/constants.sh"
   source "${SHARED_DIR}/sanitize.sh"
   source "${SHARED_DIR}/metrics.sh"
   ```
5. Read stdin JSON, validate, extract fields
6. Always exit 0 on errors
7. Add a test in `tests/<plugin>/test-<name>.sh`

## Adding a Skill

1. Create `plugins/<plugin>/skills/<skill>/SKILL.md`
2. Add `allowed-tools` frontmatter:
   ```yaml
   ---
   name: <skill-name>
   description: >
     When to trigger. What it does.
   allowed-tools:
     - Read
     - Bash
   ---
   ```
3. Register in `plugin.json` under `skills`

## Adding an Agent

1. Create `plugins/<plugin>/agents/<agent>.md`
2. Required frontmatter:
   ```yaml
   ---
   name: allay-<agent>
   model: haiku
   context: fork
   allowed-tools:
     - Read
     - Grep
     - Bash
   ---
   ```
3. Agent must be self-contained — it runs in a forked context

## Shared Code

`shared/` contains utilities sourced by all hooks:

| File | Contents |
|------|----------|
| `constants.sh` | Version, file names, size limits, thresholds |
| `metrics.sh` | `acquire_lock()`, `release_lock()`, `log_metric()` |
| `sanitize.sh` | `sanitize_path()`, `validate_json()`, `sanitize_for_log()` |
| `scripts/report-gen.sh` | Session report generator (text + optional PDF) |

Hooks resolve shared code via:
```bash
SHARED_DIR="${PLUGIN_ROOT}/../../shared"
```

## Submitting

1. `shellcheck -x` passes on all `.sh` files
2. `tests/run-all.sh` exits 0
3. No banned patterns (`flock`, `jq -s` on unbounded files, `$CLAUDE_SESSION_ID` as cache key)
4. Every SKILL.md has `allowed-tools` frontmatter
5. Every agent has `model`, `context: fork`, and `allowed-tools`
6. New hooks have corresponding tests
