#!/usr/bin/env bash
# Test: detect-drift.sh handles Glob and Grep tools (expanded matchers)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"

# Simulate Glob calls with same pattern 3x
INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Glob", tool_input: {pattern: "src/**/*.ts"}, tool_result: {files: ["src/a.ts"]}, hook_event_name: "PostToolUse"}')

for i in 1 2; do
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true
done

# Third Glob should trigger drift alert
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)

if [[ "$STDERR_OUT" != *"Drift Alert"* ]]; then
  echo "FAIL: Glob pattern repeated 3x should trigger drift alert, got: $STDERR_OUT"
  rm -f "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  rm -f "${STATE_DIR}/metrics.jsonl"
  rm -rf "${STATE_DIR}/metrics.jsonl.lock"
  exit 1
fi

# Verify turn events were logged for Glob
if ! grep -q '"tool":"Glob"' "${STATE_DIR}/metrics.jsonl" 2>/dev/null; then
  echo "FAIL: metrics.jsonl should contain turn events for Glob tool"
  rm -f "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  rm -f "${STATE_DIR}/metrics.jsonl"
  rm -rf "${STATE_DIR}/metrics.jsonl.lock"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
rm -f "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
