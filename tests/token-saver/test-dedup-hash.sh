#!/usr/bin/env bash
# Test: block-duplicates.sh blocks duplicate file reads
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/block-duplicates.sh"

# Create a test file to "read"
TEST_FILE=$(mktemp)
echo "test content line 1" > "$TEST_FILE"
echo "test content line 2" >> "$TEST_FILE"
echo "test content line 3" >> "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

# Clean any previous cache
SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/emu-reads-${SESSION_HASH}.jsonl"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PreToolUse"}')

# First read should pass (exit 0)
EXIT1=0
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" >/dev/null 2>/dev/null || EXIT1=$?

if [[ $EXIT1 -ne 0 ]]; then
  echo "FAIL: First read should exit 0, got $EXIT1"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "/tmp/emu-reads-${SESSION_HASH}.jsonl"
  exit 1
fi

# Second read of same unchanged file: hook is advisory-only per
# shared/conduct/hooks.md and the token-saver README — it must exit 0 and
# emit a "Would have blocked" advisory on stderr (not exit 2 / hard block).
EXIT2=0
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>&1 >/dev/null) || EXIT2=$?

if [[ $EXIT2 -ne 0 ]]; then
  echo "FAIL: Duplicate read advisory should exit 0 (advisory-only), got $EXIT2"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "/tmp/emu-reads-${SESSION_HASH}.jsonl"
  exit 1
fi

if ! printf "%s" "$STDERR_OUT" | grep -q "Would have blocked"; then
  echo "FAIL: Duplicate read should emit 'Would have blocked' advisory on stderr"
  echo "stderr was: $STDERR_OUT"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "/tmp/emu-reads-${SESSION_HASH}.jsonl"
  exit 1
fi

# Modify the file → third read should pass (hash changed)
echo "modified content" >> "$TEST_FILE"

EXIT3=0
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" >/dev/null 2>/dev/null || EXIT3=$?

if [[ $EXIT3 -ne 0 ]]; then
  echo "FAIL: Read of modified file should exit 0, got $EXIT3"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "/tmp/emu-reads-${SESSION_HASH}.jsonl"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "/tmp/emu-reads-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/token-saver/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/token-saver/state/metrics.jsonl.lock"

exit 0
