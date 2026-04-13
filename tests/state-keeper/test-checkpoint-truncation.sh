#!/usr/bin/env bash
# Test: checkpoint.md is truncated at 50KB limit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/state-keeper/hooks/pre-compact/save-checkpoint.sh"
STATE_DIR="${REPO_ROOT}/plugins/state-keeper/state"
CHECKPOINT="${STATE_DIR}/checkpoint.md"

# Clean state
rm -f "$CHECKPOINT" "${CHECKPOINT}.tmp" "${STATE_DIR}/metrics.jsonl"
rm -rf "${CHECKPOINT}.lock"

# Create a large CLAUDE.md that would push checkpoint over 50KB
LARGE_DIR=$(mktemp -d)
# Generate ~60KB of content
python3 -c "print('x' * 100 + '\n') * 600" > "${LARGE_DIR}/CLAUDE.md" 2>/dev/null || \
  dd if=/dev/zero bs=1024 count=60 2>/dev/null | tr '\0' 'x' > "${LARGE_DIR}/CLAUDE.md"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg cwd "$LARGE_DIR" \
  --arg session "test-truncation" \
  '{transcript_path: $transcript, cwd: $cwd, session_id: $session, hook_event_name: "PreCompact"}')

printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/state-keeper" bash "$HOOK"

# Verify checkpoint was created
if [[ ! -f "$CHECKPOINT" ]]; then
  echo "FAIL: checkpoint.md was not created"
  rm -rf "$LARGE_DIR" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify checkpoint is within 50KB + truncation notice
CHECKPOINT_SIZE=$(wc -c < "$CHECKPOINT" | tr -d ' ')
MAX_WITH_NOTICE=$((51200 + 200))  # 50KB + room for truncation notice

if [[ "$CHECKPOINT_SIZE" -gt "$MAX_WITH_NOTICE" ]]; then
  echo "FAIL: checkpoint.md is ${CHECKPOINT_SIZE} bytes, should be ≤ ${MAX_WITH_NOTICE}"
  rm -rf "$LARGE_DIR" "$MOCK_TRANSCRIPT" "$CHECKPOINT" "${STATE_DIR}/metrics.jsonl"
  rm -rf "${CHECKPOINT}.lock"
  exit 1
fi

# Verify truncation notice is present
if ! grep -q "truncated" "$CHECKPOINT"; then
  echo "FAIL: checkpoint.md should contain truncation notice"
  rm -rf "$LARGE_DIR" "$MOCK_TRANSCRIPT" "$CHECKPOINT" "${STATE_DIR}/metrics.jsonl"
  rm -rf "${CHECKPOINT}.lock"
  exit 1
fi

# Cleanup
rm -rf "$LARGE_DIR" "$MOCK_TRANSCRIPT" "$CHECKPOINT" "${STATE_DIR}/metrics.jsonl"
rm -rf "${CHECKPOINT}.lock"

exit 0
