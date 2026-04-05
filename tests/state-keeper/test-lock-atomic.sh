#!/usr/bin/env bash
# Test: mkdir-based locking works (acquire + release)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

# shellcheck source=../../shared/metrics.sh
source "${REPO_ROOT}/shared/metrics.sh"

LOCK_DIR=$(mktemp -d -u)  # -u = don't create, just give name

# Test acquire
if ! acquire_lock "$LOCK_DIR"; then
  echo "FAIL: Could not acquire lock"
  exit 1
fi

# Verify lock dir exists
if [[ ! -d "$LOCK_DIR" ]]; then
  echo "FAIL: Lock directory not created"
  exit 1
fi

# Test that second acquire fails quickly (we set retries=50 with 0.1s sleep = 5s max)
# Use a subshell with timeout to avoid waiting
SECOND_RESULT=0
(
  # Override to fail fast
  local_lock() {
    local retries=2
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
      ((retries--))
      [[ $retries -le 0 ]] && return 1
      sleep 0.1
    done
    return 0
  }
  local_lock
) && SECOND_RESULT=0 || SECOND_RESULT=1

if [[ $SECOND_RESULT -eq 0 ]]; then
  echo "FAIL: Second lock acquire should have failed"
  rmdir "$LOCK_DIR" 2>/dev/null
  exit 1
fi

# Test release
release_lock "$LOCK_DIR"

if [[ -d "$LOCK_DIR" ]]; then
  echo "FAIL: Lock directory not removed after release"
  rmdir "$LOCK_DIR" 2>/dev/null
  exit 1
fi

exit 0
