#!/usr/bin/env bash
# Test: metrics.jsonl contains properly formatted JSON entries
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

TEST_FILE=$(mktemp)
echo "static content" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"

# Trigger a drift alert (3 reads) to generate a metric
INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

for i in 1 2 3; do
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true
done

# Check metrics file has a drift_detected event
if [[ ! -f "${STATE_DIR}/metrics.jsonl" ]]; then
  echo "FAIL: metrics.jsonl should be created after drift detection"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Verify each line is valid JSON
while IFS= read -r line; do
  if ! printf "%s" "$line" | jq empty 2>/dev/null; then
    echo "FAIL: Invalid JSON in metrics.jsonl: $line"
    rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
    rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
    exit 1
  fi
done < "${STATE_DIR}/metrics.jsonl"

# Verify drift event is present
if ! grep -q "drift_detected" "${STATE_DIR}/metrics.jsonl"; then
  echo "FAIL: metrics.jsonl should contain drift_detected event"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Verify event has pattern field
if ! grep "drift_detected" "${STATE_DIR}/metrics.jsonl" | jq -e '.pattern' >/dev/null 2>&1; then
  echo "FAIL: drift_detected event should have pattern field"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
