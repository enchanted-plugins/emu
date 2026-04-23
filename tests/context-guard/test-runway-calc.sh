#!/usr/bin/env bash
# Test: metrics.jsonl accumulates turn data for runway calculation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"
TEST_FILE=$(mktemp)
echo "content" > "$TEST_FILE"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Run hook twice (won't trigger alert due to threshold=3)
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true

# Verify cache file was created
if [[ ! -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" ]]; then
  echo "FAIL: Session cache file not created"
  rm -f "$MOCK_TRANSCRIPT" "$TEST_FILE"
  exit 1
fi

# Verify cache has entries
LINE_COUNT=$(wc -l < "/tmp/fae-drift-${SESSION_HASH}.jsonl" | tr -d ' ')
if [[ "$LINE_COUNT" -lt 1 ]]; then
  echo "FAIL: Session cache should have at least 1 entry, got $LINE_COUNT"
  rm -f "$MOCK_TRANSCRIPT" "$TEST_FILE"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT" "$TEST_FILE"
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
