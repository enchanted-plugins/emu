# state-keeper

**Hook type:** PreCompact — fires before context compaction.

Preserves Claude Code context across compactions by writing a checkpoint file containing:

- Current git branch and recent commits
- Modified and staged files
- Project instructions (CLAUDE.md)
- User-flagged context (/allay:checkpoint items)

## Commands

- `/allay:checkpoint [text]` — Save context that survives compaction
- `/allay:checkpoint-show` — Display the most recent automatic checkpoint

## How it works

1. Before compaction, the PreCompact hook reads the transcript and git state
2. Writes an atomic `state/checkpoint.md` (max 50KB)
3. After compaction, the `state-recovery` skill auto-triggers to restore context

## No git? No problem.

Git sections are skipped gracefully if git is unavailable. The checkpoint still captures user-flagged context and project instructions.
