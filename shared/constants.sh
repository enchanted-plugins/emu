#!/usr/bin/env bash
# Allay shared constants — sourced by all hooks and utilities

ALLAY_VERSION="1.0.0"

# State file names
ALLAY_MEMORY_FILE="state/memory.jsonl"
ALLAY_METRICS_FILE="state/metrics.jsonl"
ALLAY_CHECKPOINT_FILE="state/checkpoint.md"
ALLAY_REMEMBER_FILE="state/remember.md"

# Size limits
ALLAY_MAX_CHECKPOINT_BYTES=51200       # 50KB
ALLAY_MAX_MEMORY_BYTES=10485760        # 10MB
ALLAY_MAX_METRICS_BYTES=10485760       # 10MB (rotate at 10MB, not 1MB)

# Duplicate read TTL
ALLAY_DUPLICATE_TTL_SECONDS=600        # 10 minutes

# Lock config
ALLAY_LOCK_SUFFIX=".lock"

# Runway / drift
ALLAY_RUNWAY_WINDOW=5
ALLAY_DRIFT_COOLDOWN_TURNS=5
ALLAY_DRIFT_READ_THRESHOLD=3
ALLAY_DRIFT_FAIL_THRESHOLD=3
