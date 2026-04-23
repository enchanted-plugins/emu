#!/usr/bin/env bash
# Test: detect-drift.sh fires alert on test fail loop (3+ consecutive failures)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "npm test"}, tool_result: {exit_code: "1"}, hook_event_name: "PostToolUse"}')

# Failures 1 and 2: should not alert
for i in 1 2; do
  STDERR_OUT=""
  STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)
  if [[ "$STDERR_OUT" == *"Drift Alert"* ]]; then
    echo "FAIL: Failure #$i should not trigger drift alert"
    rm -f "$MOCK_TRANSCRIPT"
    rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
    exit 1
  fi
done

# Failure 3: should fire alert
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" 2>&1 >/dev/null || true)

if [[ "$STDERR_OUT" != *"Drift Alert"* ]]; then
  echo "FAIL: Failure #3 should trigger drift alert, got: $STDERR_OUT"
  rm -f "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

if [[ "$STDERR_OUT" != *"failed"* ]]; then
  echo "FAIL: Alert should mention 'failed'"
  rm -f "$MOCK_TRANSCRIPT"
  rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/fae-drift-${SESSION_HASH}.jsonl" "/tmp/fae-drift-cooldown-${SESSION_HASH}"
rm -f "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/context-guard/state/metrics.jsonl.lock"

exit 0
