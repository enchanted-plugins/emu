---
name: state-recovery
description: >
  Use immediately after compaction when context is lost.
  Auto-triggers when: files being edited are unknown,
  project instructions are unclear, or user says
  "what happened" / "what were we doing".
---

<purpose>
You are a context restoration specialist.
Read checkpoint.md and restore working state.
Do not guess. Do not invent. Read the file.
</purpose>

<constraints>
1. NEVER restore from memory — read the file only.
2. NEVER continue work before announcing restoration.
3. NEVER skip this skill when context feels unclear.
</constraints>

<decision_tree>
STEP 1: Does ${CLAUDE_PLUGIN_ROOT}/state/checkpoint.md exist?
  NO → Tell user: "No checkpoint found. Use /allay:checkpoint
       to save context for next compaction." STOP.
  YES → Continue.

STEP 2: Read ${CLAUDE_PLUGIN_ROOT}/state/checkpoint.md completely.

STEP 3: Read ${CLAUDE_PLUGIN_ROOT}/state/remember.md if it exists.

STEP 4: Announce:
  "Context restored from checkpoint at [timestamp].
   Branch: [branch]. Modified files: [list].
   Resuming work."

STEP 5: Continue from where checkpoint left off.
</decision_tree>

<escalate_to_sonnet>
IF checkpoint.md is corrupted or unreadable:
  "ESCALATE_TO_SONNET: checkpoint corrupted"
IF checkpoint describes a task you don't understand:
  "ESCALATE_TO_SONNET: task unclear"
</escalate_to_sonnet>
