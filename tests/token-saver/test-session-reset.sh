#!/usr/bin/env bash
# Test: Different transcript paths produce different session caches
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/block-duplicates.sh"

# Create two different "transcripts"
TRANSCRIPT_A=$(mktemp)
TRANSCRIPT_B=$(mktemp)
echo '{"role":"user","content":"session A"}' > "$TRANSCRIPT_A"
echo '{"role":"user","content":"session B"}' > "$TRANSCRIPT_B"

TEST_FILE=$(mktemp)
echo "content" > "$TEST_FILE"

# Clean caches
HASH_A=$(md5sum "$TRANSCRIPT_A" 2>/dev/null | cut -c1-8 || echo "a")
HASH_B=$(md5sum "$TRANSCRIPT_B" 2>/dev/null | cut -c1-8 || echo "b")
rm -f "/tmp/fae-reads-${HASH_A}.jsonl" "/tmp/fae-reads-${HASH_B}.jsonl"

# Read in session A
INPUT_A=$(jq -n \
  --arg transcript "$TRANSCRIPT_A" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PreToolUse"}')

printf "%s" "$INPUT_A" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" >/dev/null 2>/dev/null || true

# Same file in session B should NOT be blocked (different session)
INPUT_B=$(jq -n \
  --arg transcript "$TRANSCRIPT_B" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PreToolUse"}')

EXIT_B=0
printf "%s" "$INPUT_B" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" >/dev/null 2>/dev/null || EXIT_B=$?

if [[ $EXIT_B -ne 0 ]]; then
  echo "FAIL: Different session should not block read, got exit $EXIT_B"
  rm -f "$TRANSCRIPT_A" "$TRANSCRIPT_B" "$TEST_FILE"
  rm -f "/tmp/fae-reads-${HASH_A}.jsonl" "/tmp/fae-reads-${HASH_B}.jsonl"
  exit 1
fi

# Cleanup
rm -f "$TRANSCRIPT_A" "$TRANSCRIPT_B" "$TEST_FILE"
rm -f "/tmp/fae-reads-${HASH_A}.jsonl" "/tmp/fae-reads-${HASH_B}.jsonl"
rm -f "${REPO_ROOT}/plugins/token-saver/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/token-saver/state/metrics.jsonl.lock"

exit 0
