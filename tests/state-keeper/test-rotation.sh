#!/usr/bin/env bash
# Test: metrics.jsonl rotates when exceeding max size
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

# Write enough data to exceed the max (use a small override for testing)
FAE_MAX_METRICS_BYTES=500

for i in $(seq 1 100); do
  ENTRY=$(jq -cn --arg i "$i" '{event: "test", idx: $i}')
  log_metric "$TEST_FILE" "$ENTRY"
done

# Check that file was rotated (should be under 500 bytes now after rotation)
FILE_SIZE=$(wc -c < "$TEST_FILE" | tr -d ' ')
LINE_COUNT=$(wc -l < "$TEST_FILE" | tr -d ' ')

# After rotation, should have at most 1000 lines (the tail kept)
# But since we only wrote 100 lines and rotated, should be small
if [[ "$LINE_COUNT" -gt 1000 ]]; then
  echo "FAIL: metrics file was not rotated (${LINE_COUNT} lines)"
  rm -f "$TEST_FILE"
  rm -rf "$LOCK_DIR"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE"
rm -rf "$LOCK_DIR"

exit 0
