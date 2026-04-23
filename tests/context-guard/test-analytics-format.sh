#!/usr/bin/env bash
# Test: detect-drift.sh logs turn events with correct format for per-tool analytics
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

TEST_FILE=$(mktemp)
echo "analytics test content" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"analytics test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"

# Run hook with different tool names
TOOLS=("Read" "Bash" "Write" "Grep" "Glob")

for tool in "${TOOLS[@]}"; do
  case "$tool" in
    Read|Grep|Glob)
      INPUT=$(jq -n \
        --arg transcript "$MOCK_TRANSCRIPT" \
        --arg tool "$tool" \
        --arg file "$TEST_FILE" \
        '{transcript_path: $transcript, cwd: "/tmp", tool_name: $tool, tool_input: {file_path: $file}, tool_result: {content: "result"}, hook_event_name: "PostToolUse"}')
      ;;
    Bash)
      INPUT=$(jq -n \
        --arg transcript "$MOCK_TRANSCRIPT" \
        '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "echo hello"}, tool_result: {exit_code: "0", content: "hello"}, hook_event_name: "PostToolUse"}')
      ;;
    Write)
      INPUT=$(jq -n \
        --arg transcript "$MOCK_TRANSCRIPT" \
        --arg file "$TEST_FILE" \
        '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, tool_result: {}, hook_event_name: "PostToolUse"}')
      ;;
  esac

  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true
done

# Verify metrics file exists
if [[ ! -f "${STATE_DIR}/metrics.jsonl" ]]; then
  echo "FAIL: metrics.jsonl should be created"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Verify turn events for each tool
for tool in "${TOOLS[@]}"; do
  if ! grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | grep -q "\"tool\":\"${tool}\""; then
    echo "FAIL: missing turn event for tool: $tool"
    rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
    rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
    rm -f "${STATE_DIR}/metrics.jsonl"
    rm -rf "${STATE_DIR}/metrics.jsonl.lock"
    exit 1
  fi
done

# Verify each turn event has required fields: event, ts, tool, tokens_est, turn
TURN_LINE=$(grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | head -1)

for field in "event" "ts" "tool" "tokens_est" "turn"; do
  VALUE=$(printf "%s" "$TURN_LINE" | jq -r ".${field} // empty" 2>/dev/null)
  if [[ -z "$VALUE" ]] || [[ "$VALUE" == "null" ]]; then
    echo "FAIL: turn event missing required field: $field"
    rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
    rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
    rm -f "${STATE_DIR}/metrics.jsonl"
    rm -rf "${STATE_DIR}/metrics.jsonl.lock"
    exit 1
  fi
done

# Verify tokens_est is a positive number
TOKENS=$(printf "%s" "$TURN_LINE" | jq -r '.tokens_est' 2>/dev/null)
if [[ "$TOKENS" -le 0 ]] 2>/dev/null; then
  echo "FAIL: tokens_est should be positive, got $TOKENS"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  rm -f "${STATE_DIR}/metrics.jsonl"
  rm -rf "${STATE_DIR}/metrics.jsonl.lock"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
