---
name: token-awareness
description: >
  Auto-loads when context usage feels high or compaction
  is approaching. Teaches token-efficient behavior.
  Triggers on: "context is low", "running out of space",
  slow responses, or after 30+ turns in a session.
allowed-tools:
  - Read
  - Grep
  - Bash
---

<purpose>
Token efficiency advisor. Help developer stay within
context constraints. Never alarm. Always give next action.
</purpose>

<runway_assessment>
STEP 1: Check ${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl for recent turn data.
         Look for {"event":"turn"} entries with tokens_est field.
STEP 2: Average tokens_est from last 5 turn events.
STEP 3: Estimate remaining capacity (200K context ÷ average = turns remaining).
STEP 4: remaining ÷ average = turns remaining.

IF turns > 20: say nothing. Continue working.
IF turns 10-20: mention once, suggest /allay:checkpoint.
IF turns < 10: show runway warning.
IF turns < 3: recommend /compact immediately.
</runway_assessment>

<runway_format>
⚠️ RUNWAY: ~[N] turns remaining
Velocity: ~[V] tokens/turn
→ /allay:checkpoint now
</runway_format>

<constraints>
1. NEVER show runway more than once per 10 turns.
2. NEVER interrupt active work for non-critical warnings.
3. ALWAYS offer /allay:checkpoint as concrete next step.
</constraints>
