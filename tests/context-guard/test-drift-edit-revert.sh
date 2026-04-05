#!/usr/bin/env bash
# Test: detect-drift.sh fires alert on edit-revert cycle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"

TEST_FILE=$(mktemp)
MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"

# Write version A
echo "version A content" > "$TEST_FILE"
INPUT_A=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

printf "%s" "$INPUT_A" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true

# Write version B
echo "version B content" > "$TEST_FILE"
INPUT_B=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

printf "%s" "$INPUT_B" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true

# Revert to version A (same hash as first write)
echo "version A content" > "$TEST_FILE"
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT_A" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)

if [[ "$STDERR_OUT" != *"Drift Alert"* ]]; then
  echo "FAIL: Revert to previous hash should trigger drift alert, got: $STDERR_OUT"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

if [[ "$STDERR_OUT" != *"reverted"* ]]; then
  echo "FAIL: Alert should mention 'reverted'"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
rm -f "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl.lock"

exit 0
