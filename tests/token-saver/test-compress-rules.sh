#!/usr/bin/env bash
# Test: compress-bash.sh applies compression rules correctly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/compress-bash.sh"
STATE_DIR="${REPO_ROOT}/plugins/token-saver/state"

rm -f "${STATE_DIR}/metrics.jsonl"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

# Test 1: npm test → should append tail
INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "npm test"}, hook_event_name: "PreToolUse"}')

OUTPUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>/dev/null || true)

if [[ -z "$OUTPUT" ]]; then
  echo "FAIL: npm test should produce updatedInput output"
  rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
  exit 1
fi

if ! printf "%s" "$OUTPUT" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1; then
  echo "FAIL: output should contain hookSpecificOutput.updatedInput.command"
  rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
  exit 1
fi

MODIFIED_CMD=$(printf "%s" "$OUTPUT" | jq -r '.hookSpecificOutput.updatedInput.command' 2>/dev/null)
if [[ "$MODIFIED_CMD" != *"tail -n 40"* ]]; then
  echo "FAIL: npm test should be compressed with tail -n 40, got: $MODIFIED_CMD"
  rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
  exit 1
fi

# Test 2: find . → should append head
INPUT2=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "find . -name \"*.js\""}, hook_event_name: "PreToolUse"}')

OUTPUT2=$(printf "%s" "$INPUT2" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>/dev/null || true)

MODIFIED_CMD2=$(printf "%s" "$OUTPUT2" | jq -r '.hookSpecificOutput.updatedInput.command' 2>/dev/null)
if [[ "$MODIFIED_CMD2" != *"head -n 30"* ]]; then
  echo "FAIL: find should be compressed with head -n 30, got: $MODIFIED_CMD2"
  rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
