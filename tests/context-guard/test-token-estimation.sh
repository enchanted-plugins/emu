#!/usr/bin/env bash
# Test: detect-drift.sh logs token estimation ("turn" events) to metrics.jsonl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

TEST_FILE=$(mktemp)
echo "some file content for token estimation" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, tool_result: {content: "some file content"}, hook_event_name: "PostToolUse"}')

# Run hook once
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true

# Verify metrics.jsonl has a "turn" event
if [[ ! -f "${STATE_DIR}/metrics.jsonl" ]]; then
  echo "FAIL: metrics.jsonl should be created"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

if ! grep -q '"event":"turn"' "${STATE_DIR}/metrics.jsonl"; then
  echo "FAIL: metrics.jsonl should contain turn event"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Verify turn event has tokens_est field
TOKENS_EST=$(grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | head -1 | jq -r '.tokens_est // empty' 2>/dev/null)

if [[ -z "$TOKENS_EST" ]] || [[ "$TOKENS_EST" == "null" ]]; then
  echo "FAIL: turn event should have tokens_est field"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

if [[ "$TOKENS_EST" -lt 50 ]]; then
  echo "FAIL: tokens_est should be at least 50 (minimum), got $TOKENS_EST"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Verify turn event has tool field
TOOL_NAME=$(grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | head -1 | jq -r '.tool // empty' 2>/dev/null)

if [[ "$TOOL_NAME" != "Read" ]]; then
  echo "FAIL: turn event tool should be 'Read', got '$TOOL_NAME'"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
