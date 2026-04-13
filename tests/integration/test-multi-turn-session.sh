#!/usr/bin/env bash
# Integration test: simulate a multi-turn session with all 3 plugins active
# Verifies that hooks compose correctly and metrics are written by each plugin.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

CG_HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
TS_COMPRESS="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/compress-bash.sh"
TS_DEDUP="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/block-duplicates.sh"
SK_HOOK="${REPO_ROOT}/plugins/state-keeper/hooks/pre-compact/save-checkpoint.sh"

CG_STATE="${REPO_ROOT}/plugins/context-guard/state"
TS_STATE="${REPO_ROOT}/plugins/token-saver/state"
SK_STATE="${REPO_ROOT}/plugins/state-keeper/state"

# Clean all state
rm -f "${CG_STATE}/metrics.jsonl" "${TS_STATE}/metrics.jsonl" "${SK_STATE}/metrics.jsonl"
rm -rf "${CG_STATE}/metrics.jsonl.lock" "${TS_STATE}/metrics.jsonl.lock" "${SK_STATE}/metrics.jsonl.lock"
rm -f "${SK_STATE}/checkpoint.md" "${SK_STATE}/checkpoint.md.tmp"
rm -rf "${SK_STATE}/checkpoint.md.lock"

# Create test fixtures
TEST_FILE=$(mktemp)
echo "line 1" > "$TEST_FILE"
echo "line 2" >> "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"integration test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
rm -f "/tmp/allay-reads-${SESSION_HASH}.jsonl"
rm -rf "/tmp/allay-delta-${SESSION_HASH}"

# ── Turn 1: Bash command (token-saver compresses, context-guard tracks) ──
BASH_INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "npm test"}, hook_event_name: "PreToolUse"}')

COMPRESS_OUTPUT=$(printf "%s" "$BASH_INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$TS_COMPRESS" 2>/dev/null || true)

if [[ -z "$COMPRESS_OUTPUT" ]]; then
  echo "FAIL: token-saver should compress 'npm test'"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# PostToolUse for Bash
BASH_POST=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: "npm test"}, tool_result: {exit_code: "0", stdout: "tests passed"}, hook_event_name: "PostToolUse"}')

printf "%s" "$BASH_POST" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$CG_HOOK" >/dev/null 2>/dev/null || true

# ── Turn 2: Read file (token-saver allows, context-guard tracks) ──
READ_INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, hook_event_name: "PreToolUse"}')

EXIT_READ1=0
printf "%s" "$READ_INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$TS_DEDUP" >/dev/null 2>/dev/null || EXIT_READ1=$?

if [[ $EXIT_READ1 -ne 0 ]]; then
  echo "FAIL: First read should pass (exit 0), got $EXIT_READ1"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

READ_POST=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Read", tool_input: {file_path: $file}, tool_result: {content: "line 1\nline 2"}, hook_event_name: "PostToolUse"}')

printf "%s" "$READ_POST" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$CG_HOOK" >/dev/null 2>/dev/null || true

# ── Turn 3: Duplicate read (token-saver blocks) ──
EXIT_READ2=0
printf "%s" "$READ_INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$TS_DEDUP" >/dev/null 2>/dev/null || EXIT_READ2=$?

if [[ $EXIT_READ2 -ne 2 ]]; then
  echo "FAIL: Duplicate read should be blocked (exit 2), got $EXIT_READ2"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# ── Turn 4: PreCompact (state-keeper saves checkpoint) ──
COMPACT_INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg cwd "$REPO_ROOT" \
  --arg session "integration-test" \
  '{transcript_path: $transcript, cwd: $cwd, session_id: $session, hook_event_name: "PreCompact"}')

printf "%s" "$COMPACT_INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/state-keeper" bash "$SK_HOOK"

# ── Verify all metrics exist ──
if [[ ! -f "${CG_STATE}/metrics.jsonl" ]]; then
  echo "FAIL: context-guard metrics.jsonl missing"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

if [[ ! -f "${TS_STATE}/metrics.jsonl" ]]; then
  echo "FAIL: token-saver metrics.jsonl missing"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

if [[ ! -f "${SK_STATE}/metrics.jsonl" ]]; then
  echo "FAIL: state-keeper metrics.jsonl missing"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify context-guard has turn events
if ! grep -q '"event":"turn"' "${CG_STATE}/metrics.jsonl"; then
  echo "FAIL: context-guard should have turn events"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify token-saver has compression and dedup events
if ! grep -q '"bash_compressed\|duplicate_blocked"' "${TS_STATE}/metrics.jsonl"; then
  echo "FAIL: token-saver should have compression or dedup events"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify state-keeper has checkpoint event
if ! grep -q '"checkpoint_saved"' "${SK_STATE}/metrics.jsonl"; then
  echo "FAIL: state-keeper should have checkpoint_saved event"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify checkpoint.md was created
if [[ ! -f "${SK_STATE}/checkpoint.md" ]]; then
  echo "FAIL: checkpoint.md should exist"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/allay-drift-${SESSION_HASH}.jsonl" "/tmp/allay-drift-cooldown-${SESSION_HASH}"
rm -f "/tmp/allay-reads-${SESSION_HASH}.jsonl"
rm -rf "/tmp/allay-delta-${SESSION_HASH}"
rm -f "${CG_STATE}/metrics.jsonl" "${TS_STATE}/metrics.jsonl" "${SK_STATE}/metrics.jsonl"
rm -rf "${CG_STATE}/metrics.jsonl.lock" "${TS_STATE}/metrics.jsonl.lock" "${SK_STATE}/metrics.jsonl.lock"
rm -f "${SK_STATE}/checkpoint.md" "${SK_STATE}/checkpoint.md.tmp"
rm -rf "${SK_STATE}/checkpoint.md.lock"

exit 0
