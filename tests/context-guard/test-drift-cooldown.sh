#!/usr/bin/env bash
# Test: drift alert has 5-turn cooldown (no repeat alerts within 5 turns)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"

TEST_FILE=$(mktemp)
echo "static content" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Reads 1-3: third should fire alert
for i in 1 2 3; do
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true
done

# Reads 4-5: should be within cooldown, no alert
for i in 4 5; do
  STDERR_OUT=""
  STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)
  if [[ "$STDERR_OUT" == *"Drift Alert"* ]]; then
    echo "FAIL: Read #$i should be within cooldown (no alert)"
    rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
    rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
    exit 1
  fi
done

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
rm -f "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl.lock"

exit 0
