#!/usr/bin/env bash
# Test: FULL: prefix bypasses compression
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/compress-bash.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

# FULL: prefix should produce no output (exit 0 silently)
INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "FULL: npm test"}, hook_event_name: "PreToolUse"}')

OUTPUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>/dev/null || true)

if [[ -n "$OUTPUT" ]]; then
  echo "FAIL: FULL: prefix should produce no output, got: $OUTPUT"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Also test piped commands are skipped
INPUT2=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "npm test | grep PASS"}, hook_event_name: "PreToolUse"}')

OUTPUT2=$(printf "%s" "$INPUT2" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>/dev/null || true)

if [[ -n "$OUTPUT2" ]]; then
  echo "FAIL: already-piped command should produce no output, got: $OUTPUT2"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"

exit 0
