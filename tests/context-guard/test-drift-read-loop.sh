#!/usr/bin/env bash
# Test: detect-drift.sh fires alert on read loop (same file read 3+ times)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"

# Create a test file that won't change
TEST_FILE=$(mktemp)
echo "static content" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

# Clean caches
SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Read 1 and 2: should not alert
for i in 1 2; do
  STDERR_OUT=""
  STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)
  if [[ "$STDERR_OUT" == *"Drift Alert"* ]]; then
    echo "FAIL: Read #$i should not trigger drift alert"
    rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
    rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
    exit 1
  fi
done

# Read 3: should fire alert
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)

if [[ "$STDERR_OUT" != *"Drift Alert"* ]]; then
  echo "FAIL: Read #3 should trigger drift alert, got: $STDERR_OUT"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

if [[ "$STDERR_OUT" != *"read"*"without changes"* ]]; then
  echo "FAIL: Alert should mention 'read' and 'without changes'"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
rm -f "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl.lock"

exit 0
