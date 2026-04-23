# state-keeper

**Hook type:** PreCompact — fires before context compaction.

## Install

Part of the [Emu](../..) bundle. The simplest install is the `full` meta-plugin, which pulls in all 3 Emu plugins via dependency resolution:

```
/plugin marketplace add enchanted-plugins/fae
/plugin install full@fae
```

To install this plugin on its own: `/plugin install fae-state-keeper@fae`. `state-keeper` writes checkpoints that `context-guard`'s runway forecast reads to recalibrate after compaction, and `token-saver`'s compression extends the turns before compaction fires in the first place — so on its own checkpoints go unread and compactions fire more often.

## Components

| Type | Name | Description |
|------|------|-------------|
| Hook | save-checkpoint.sh | Writes checkpoint.md before compaction wipes context |
| Skill | state-recovery | Restores context after compaction |
| Command | /fae:checkpoint | Save/view user-flagged context |
| Command | /fae:checkpoint-show | Display most recent automatic checkpoint |
| Agent | restorer | Autonomous context restoration (Haiku, forked) |

## Architecture

```
PreCompact
    │
    ▼
save-checkpoint.sh
    │
    ├── Read git state (branch, modified, staged, log)
    ├── Read CLAUDE.md (first 50 lines)
    ├── Read state/remember.md (user-flagged items)
    ├── Build markdown checkpoint (heredoc template)
    ├── Enforce 50KB limit (truncate with notice)
    ├── Write atomically (mkdir lock → tmpfile → mv)
    └── Log checkpoint_saved metric
        │
        ▼
    state/checkpoint.md

                After compaction
                      │
                      ▼
              state-recovery skill
              (or restorer agent)
                      │
                      ├── Read checkpoint.md
                      ├── Read remember.md
                      └── Announce restoration
```

## How It Works

1. Before compaction, the PreCompact hook gathers git state and project instructions
2. Writes an atomic `state/checkpoint.md` (max 50KB, truncated if larger)
3. After compaction, the `state-recovery` skill auto-triggers to restore context
4. The `restorer` agent can handle restoration autonomously in the background

## No Git? No Problem.

Git sections are skipped gracefully if git is unavailable.
The checkpoint still captures user-flagged context and project instructions.

## Commands

- `/fae:checkpoint <text>` — Append text to `state/remember.md` with timestamp. Survives compaction.
- `/fae:checkpoint` — Display all saved items.
- `/fae:checkpoint-show` — Display the most recent automatic checkpoint with age.

## Behavioral modules

Inherits the [shared behavioral modules](../../shared/) via root [CLAUDE.md](../../CLAUDE.md) — discipline, context, verification, delegation, failure-modes, tool-use, skill-authoring, hooks, precedent.
