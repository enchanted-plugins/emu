#!/usr/bin/env bash
# Emu shared constants — sourced by all hooks and utilities

FAE_VERSION="2.0.0"

# State file names
FAE_MEMORY_FILE="state/memory.jsonl"
FAE_METRICS_FILE="state/metrics.jsonl"
FAE_CHECKPOINT_FILE="state/checkpoint.md"
FAE_REMEMBER_FILE="state/remember.md"

# Size limits
FAE_MAX_CHECKPOINT_BYTES=51200       # 50KB
FAE_MAX_MEMORY_BYTES=10485760        # 10MB
FAE_MAX_METRICS_BYTES=10485760       # 10MB (rotate at 10MB, not 1MB)

# Duplicate read TTL
FAE_DUPLICATE_TTL_SECONDS=600        # 10 minutes

# Lock config
FAE_LOCK_SUFFIX=".lock"

# Runway / drift
FAE_RUNWAY_WINDOW=5
FAE_DRIFT_COOLDOWN_TURNS=5
FAE_DRIFT_READ_THRESHOLD=3
FAE_DRIFT_FAIL_THRESHOLD=3

# A8 — Skill-Scoped Attribution
# TTL after which an un-unregistered skill scope is considered stale and evicted.
# Default: 1h. Override via FAE_SKILL_TTL env var.
FAE_SKILL_TTL="${FAE_SKILL_TTL:-3600}"
FAE_ACTIVE_SKILLS_FILE="state/active-skills.json"
FAE_SKILL_METRICS_FILE="state/skill-metrics.jsonl"
FAE_SESSION_MARKER_FILE="state/.session"

# A9 — Worktree Session Graph
# XDG-compliant global state layout. Metrics → STATE, learnings → DATA.
# Spec: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
FAE_XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
FAE_XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
FAE_GLOBAL_STATE_SUBDIR="fae"
FAE_GLOBAL_DATA_SUBDIR="fae"
