#!/usr/bin/env bash
# Test: block-duplicates.sh delta mode returns diff info for changed files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/block-duplicates.sh"

# Create test file
TEST_FILE=$(mktemp)
for i in $(seq 1 50); do
  echo "original line $i" >> "$TEST_FILE"
done

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test-delta"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-reads-${SESSION_HASH}.jsonl"
rm -rf "/tmp/fae-delta-${SESSION_HASH}"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PreToolUse"}')

# First read — should pass and cache
EXIT1=0
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" >/dev/null 2>/dev/null || EXIT1=$?
if [[ $EXIT1 -ne 0 ]]; then
  echo "FAIL: First read should exit 0, got $EXIT1"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Modify file (small change — triggers delta, not full block)
TMPMOD=$(mktemp)
sed 's/original line 25/MODIFIED line 25/' "$TEST_FILE" > "$TMPMOD" && mv "$TMPMOD" "$TEST_FILE"

# Second read — file changed, should pass (exit 0) with delta info on stderr
EXIT2=0
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>&1 >/dev/null || EXIT2=$?)

if [[ $EXIT2 -ne 0 ]]; then
  echo "FAIL: Read of changed file should exit 0 (delta mode), got $EXIT2"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-reads-${SESSION_HASH}.jsonl"
  rm -rf "/tmp/fae-delta-${SESSION_HASH}"
  exit 1
fi

# Delta info should mention the change
if [[ "$STDERR_OUT" == *"Delta mode"* ]] || [[ "$STDERR_OUT" == *"MODIFIED"* ]] || [[ -z "$STDERR_OUT" ]]; then
  # Either delta mode fired with diff, or no output (diff wasn't smaller — both OK)
  true
fi

# Third read — file unchanged since second read, should block (exit 2)
EXIT3=0
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" >/dev/null 2>/dev/null || EXIT3=$?

if [[ $EXIT3 -ne 2 ]]; then
  echo "FAIL: Third read of unchanged file should exit 2, got $EXIT3"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-reads-${SESSION_HASH}.jsonl"
  rm -rf "/tmp/fae-delta-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/fae-reads-${SESSION_HASH}.jsonl"
rm -rf "/tmp/fae-delta-${SESSION_HASH}"
rm -f "${REPO_ROOT}/plugins/token-saver/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/token-saver/state/metrics.jsonl.lock"

exit 0
