---
name: fae:checkpoint
description: >
  Save important context that survives compaction.
  /fae:checkpoint <text> — saves text to remember.md.
  /fae:checkpoint — shows saved items.
---

When the user runs `/fae:checkpoint` with text after it:

1. Read the text provided after the command.
2. Append it to the file at `${CLAUDE_PLUGIN_ROOT}/state/remember.md` with an ISO 8601 UTC timestamp prefix.
3. Confirm with: `✓ Checkpointed: [first 80 chars of text]. Survives compaction.`
4. Log `{"event":"manual_checkpoint","ts":"..."}` to `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl`.

When the user runs `/fae:checkpoint` without text:

1. Read `${CLAUDE_PLUGIN_ROOT}/state/remember.md`.
2. If it exists and has content: display the full contents.
3. If it doesn't exist or is empty: say "No items checkpointed yet. Use `/fae:checkpoint <text>` to save context that survives compaction."
