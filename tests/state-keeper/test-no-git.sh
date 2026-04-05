#!/usr/bin/env bash
# Test: PreCompact hook works gracefully without git
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/state-keeper/hooks/pre-compact/save-checkpoint.sh"
STATE_DIR="${REPO_ROOT}/plugins/state-keeper/state"
CHECKPOINT="${STATE_DIR}/checkpoint.md"

# Clean state
rm -f "$CHECKPOINT" "${CHECKPOINT}.tmp" "${STATE_DIR}/metrics.jsonl"
rm -rf "${CHECKPOINT}.lock"

# Create a temp directory with no git
NO_GIT_DIR=$(mktemp -d)
MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg cwd "$NO_GIT_DIR" \
  --arg session "test-no-git" \
  '{transcript_path: $transcript, cwd: $cwd, session_id: $session, hook_event_name: "PreCompact"}')

printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/state-keeper" bash "$HOOK"

# Hook must exit 0 (checked by set -e above)

# Checkpoint should still be created
if [[ ! -f "$CHECKPOINT" ]]; then
  echo "FAIL: checkpoint.md not created in no-git scenario"
  rm -rf "$NO_GIT_DIR" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Branch section should show N/A
if ! grep -q "N/A" "$CHECKPOINT"; then
  echo "FAIL: checkpoint.md should show N/A for branch without git"
  rm -rf "$NO_GIT_DIR" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -rf "$NO_GIT_DIR" "$MOCK_TRANSCRIPT" "$CHECKPOINT" "${STATE_DIR}/metrics.jsonl"
rm -rf "${CHECKPOINT}.lock"

exit 0
