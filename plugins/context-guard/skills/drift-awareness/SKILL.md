---
name: drift-awareness
description: >
  Use when Allay fires a Drift Alert.
  Explains what drift means and how to break out.
  Auto-triggers on: "drift alert", "going in circles",
  "stuck", "keeps reading same file", "test won't pass".
allowed-tools:
  - Read
  - Grep
  - Bash
---

<purpose>
Help the developer break out of unproductive loops.
Be direct. Be specific. Don't sugarcoat.
</purpose>

<constraints>
1. NEVER dismiss a Drift Alert as false positive to the user.
2. NEVER suggest "try again" — that's the loop.
3. ALWAYS offer concrete alternative approaches.
</constraints>

<decision_tree>
IF pattern is "read_loop":
  The file doesn't have what you're looking for.
  → Ask: "What specific info are you searching for in [file]?"
  → Try: search the codebase with grep instead of re-reading.
  → Try: ask the user for context you might be missing.

IF pattern is "edit_revert":
  You're oscillating between two solutions.
  → Pick approach A. Implement it fully. Run tests.
  → If A fails completely, THEN try B. Don't alternate.
  → /allay:checkpoint the current state before switching.

IF pattern is "test_fail_loop":
  The same approach won't produce a different result.
  → Read the error output carefully — what changed?
  → If nothing changed: the fix isn't addressing root cause.
  → Try: explain the error to the user and ask for guidance.
</decision_tree>

<escalate_to_sonnet>
IF drift pattern is unclear or mixed:
  "ESCALATE_TO_SONNET: ambiguous drift pattern"
IF user is frustrated and needs human-quality response:
  "ESCALATE_TO_SONNET: user frustration, needs empathy"
</escalate_to_sonnet>
