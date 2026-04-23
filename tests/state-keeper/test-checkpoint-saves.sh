#!/usr/bin/env bash
# Test: PreCompact hook saves a checkpoint.md file
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/state-keeper/hooks/pre-compact/save-checkpoint.sh"
STATE_DIR="${REPO_ROOT}/plugins/state-keeper/state"
CHECKPOINT="${STATE_DIR}/checkpoint.md"

# Clean state
rm -f "$CHECKPOINT" "${CHECKPOINT}.tmp" "${STATE_DIR}/metrics.jsonl"
rm -rf "${CHECKPOINT}.lock"

# Create a mock transcript
MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

# Pipe mock stdin JSON to hook
INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg cwd "$REPO_ROOT" \
  --arg session "test-session" \
  '{transcript_path: $transcript, cwd: $cwd, session_id: $session, hook_event_name: "PreCompact"}')

printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/state-keeper" bash "$HOOK"

# Verify checkpoint was created
if [[ ! -f "$CHECKPOINT" ]]; then
  echo "FAIL: checkpoint.md was not created"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify checkpoint contains expected sections
if ! grep -q "# Emu Checkpoint" "$CHECKPOINT"; then
  echo "FAIL: checkpoint.md missing header"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

if ! grep -q "## Branch" "$CHECKPOINT"; then
  echo "FAIL: checkpoint.md missing Branch section"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify metric was logged
if [[ ! -f "${STATE_DIR}/metrics.jsonl" ]]; then
  echo "FAIL: metrics.jsonl was not created"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

if ! grep -q "checkpoint_saved" "${STATE_DIR}/metrics.jsonl"; then
  echo "FAIL: metrics.jsonl missing checkpoint_saved event"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT" "$CHECKPOINT" "${STATE_DIR}/metrics.jsonl"
rm -rf "${CHECKPOINT}.lock"

exit 0
