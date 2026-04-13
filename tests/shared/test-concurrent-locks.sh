#!/usr/bin/env bash
# Test: concurrent hook invocations don't corrupt metrics.jsonl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

# shellcheck source=../../shared/constants.sh
source "${REPO_ROOT}/shared/constants.sh"
# shellcheck source=../../shared/metrics.sh
source "${REPO_ROOT}/shared/metrics.sh"

# Create a temp metrics file
TEST_FILE=$(mktemp)
LOCK_DIR="${TEST_FILE}.lock"

rm -f "$TEST_FILE"
rm -rf "$LOCK_DIR"

# Launch 10 concurrent writers
PIDS=()
for i in $(seq 1 10); do
  (
    ENTRY=$(jq -cn --arg i "$i" --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{event: "concurrent_test", idx: $i, ts: $ts}')
    log_metric "$TEST_FILE" "$ENTRY"
  ) &
  PIDS+=($!)
done

# Wait for all to finish
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done

# Verify file exists and has entries
if [[ ! -f "$TEST_FILE" ]]; then
  echo "FAIL: metrics file should exist after concurrent writes"
  exit 1
fi

LINE_COUNT=$(wc -l < "$TEST_FILE" | tr -d ' ')
if [[ "$LINE_COUNT" -lt 5 ]]; then
  echo "FAIL: expected at least 5 lines from concurrent writes, got $LINE_COUNT"
  rm -f "$TEST_FILE"
  rm -rf "$LOCK_DIR"
  exit 1
fi

# Verify every line is valid JSON
INVALID=0
while IFS= read -r line; do
  if [[ -n "$line" ]] && ! printf "%s" "$line" | jq empty 2>/dev/null; then
    INVALID=$((INVALID + 1))
  fi
done < "$TEST_FILE"

if [[ "$INVALID" -gt 0 ]]; then
  echo "FAIL: $INVALID lines of invalid JSON after concurrent writes"
  rm -f "$TEST_FILE"
  rm -rf "$LOCK_DIR"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE"
rm -rf "$LOCK_DIR"

exit 0
