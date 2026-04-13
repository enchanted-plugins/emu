# state-keeper

**Hook type:** PreCompact — fires before context compaction.

## Components

| Type | Name | Description |
|------|------|-------------|
| Hook | save-checkpoint.sh | Writes checkpoint.md before compaction wipes context |
| Skill | state-recovery | Restores context after compaction |
| Command | /allay:checkpoint | Save/view user-flagged context |
| Command | /allay:checkpoint-show | Display most recent automatic checkpoint |
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

- `/allay:checkpoint <text>` — Append text to `state/remember.md` with timestamp. Survives compaction.
- `/allay:checkpoint` — Display all saved items.
- `/allay:checkpoint-show` — Display the most recent automatic checkpoint with age.
