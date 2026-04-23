#!/usr/bin/env bash
# Test: A9 — global skill-metrics-global.*.jsonl contains entries from
# multiple worktrees, keyed on the same repo_id.
#
# Simulates two worktrees of the same repo by overriding FAE_INIT_CWD +
# FAE_WORKTREE_REL via direct env exports into the hook. Verifies the global
# dir receives rows from both worktree identities and groups correctly by repo_id.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

# Isolate XDG_STATE_HOME for this test so we don't pollute the developer's real dir.
FAKE_XDG=$(mktemp -d)
export XDG_STATE_HOME="$FAKE_XDG"

cleanup() {
  rm -rf "$FAKE_XDG" 2>/dev/null || true
  rm -f "${STATE_DIR}/metrics.jsonl" "${STATE_DIR}/skill-metrics.jsonl" 2>/dev/null || true
  rm -rf "${STATE_DIR}/metrics.jsonl.lock" "${STATE_DIR}/skill-metrics.jsonl.lock" 2>/dev/null || true
  [[ -n "${TF:-}" ]] && rm -f "$TF"
  [[ -n "${MT:-}" ]] && rm -f "$MT"
  [[ -n "${SH:-}" ]] && rm -f "/tmp/fae-drift-${SH}.jsonl" "/tmp/fae-drift-cooldown-${SH}"
}
trap cleanup EXIT

rm -f "${STATE_DIR}/metrics.jsonl" "${STATE_DIR}/skill-metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

TF=$(mktemp); echo "wt" > "$TF"
MT=$(mktemp); echo '{"role":"user"}' > "$MT"
SH=$(md5sum "$MT" | cut -c1-8)

INPUT=$(jq -n --arg t "$MT" --arg f "$TF" '{transcript_path:$t, cwd:"/tmp", tool_name:"Read", tool_input:{file_path:$f}, tool_result:{content:"x"}, hook_event_name:"PostToolUse"}')

# ── Fire from "main" worktree ──
printf "%s" "$INPUT" | \
  CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" \
  FAE_REPO_ID="deadbeef1234" \
  FAE_WORKTREE_PATH="/repo/main" \
  FAE_WORKTREE_REL="." \
  FAE_MAIN_WORKTREE="/repo/main" \
  FAE_IS_WORKTREE="0" \
  FAE_SESSION_ID="sessmain0000" \
  FAE_GLOBAL_STATE_DIR="${FAKE_XDG}/fae/deadbeef1234" \
  bash "$HOOK" >/dev/null 2>/dev/null || true

# ── Fire from "worktree" (apps/sigil) ──
# Reset the drift cache so the cooldown doesn't eat this call.
rm -f "/tmp/fae-drift-${SH}.jsonl" "/tmp/fae-drift-cooldown-${SH}"
# Use a different transcript so SESSION_HASH differs and turn 1 resets.
MT2=$(mktemp); echo '{"role":"user","content":"wt2"}' > "$MT2"
INPUT2=$(jq -n --arg t "$MT2" --arg f "$TF" '{transcript_path:$t, cwd:"/tmp", tool_name:"Read", tool_input:{file_path:$f}, tool_result:{content:"x"}, hook_event_name:"PostToolUse"}')

printf "%s" "$INPUT2" | \
  CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" \
  FAE_REPO_ID="deadbeef1234" \
  FAE_WORKTREE_PATH="/repo/worktrees/sigil" \
  FAE_WORKTREE_REL="apps/sigil" \
  FAE_MAIN_WORKTREE="/repo/main" \
  FAE_IS_WORKTREE="1" \
  FAE_SESSION_ID="sessworktree" \
  FAE_GLOBAL_STATE_DIR="${FAKE_XDG}/fae/deadbeef1234" \
  bash "$HOOK" >/dev/null 2>/dev/null || true

rm -f "$MT2"

# ── Verify global dir has rows from BOTH worktrees ──
GLOBAL_DIR="${FAKE_XDG}/fae/deadbeef1234"
if [[ ! -d "$GLOBAL_DIR" ]]; then
  echo "FAIL: global state dir not created: $GLOBAL_DIR"
  exit 1
fi

SHARDS=("$GLOBAL_DIR"/skill-metrics-global.*.jsonl)
if [[ ! -f "${SHARDS[0]}" ]]; then
  echo "FAIL: no global shard files found in $GLOBAL_DIR"
  ls -la "$GLOBAL_DIR" >&2
  exit 1
fi

# Collect distinct worktree values across all shards
DISTINCT=$(cat "${SHARDS[@]}" 2>/dev/null | jq -r '.worktree' | sort -u)
COUNT=$(printf "%s\n" "$DISTINCT" | grep -cv '^$' || true)

if [[ "$COUNT" -lt 2 ]]; then
  echo "FAIL: expected ≥2 distinct worktrees in global shards, got $COUNT"
  echo "Distinct worktrees: $DISTINCT"
  exit 1
fi

# Verify both "." and "apps/sigil" are present
if ! printf "%s\n" "$DISTINCT" | grep -qx '\.'; then
  echo "FAIL: main worktree ('.') missing from global shards"
  echo "Distinct: $DISTINCT"
  exit 1
fi
if ! printf "%s\n" "$DISTINCT" | grep -qx 'apps/sigil'; then
  echo "FAIL: worktree 'apps/sigil' missing from global shards"
  echo "Distinct: $DISTINCT"
  exit 1
fi

# repo_id must be identical across rows (that's the whole point of A9)
DISTINCT_REPO=$(cat "${SHARDS[@]}" 2>/dev/null | jq -r '.repo_id' | sort -u | grep -cv '^$' || true)
if [[ "$DISTINCT_REPO" -ne 1 ]]; then
  echo "FAIL: expected single repo_id across worktrees, got $DISTINCT_REPO distinct"
  exit 1
fi

exit 0
