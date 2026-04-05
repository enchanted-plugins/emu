---
name: allay:checkpoint-show
description: Display the most recent automatic checkpoint saved before compaction.
---

When the user runs `/allay:checkpoint-show`:

1. Check if `${CLAUDE_PLUGIN_ROOT}/state/checkpoint.md` exists.
2. If it exists:
   - Display the full contents of the checkpoint file.
   - Calculate and show the age (how long ago it was created) from the timestamp in the file.
3. If it does not exist:
   - Say: "No automatic checkpoint yet. One will be created automatically before the next compaction."
