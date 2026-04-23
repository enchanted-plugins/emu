#!/usr/bin/env bash
# Test: detect-drift.sh attributes every event to the currently-active skill.
#
# Verifies:
#   - No skill registered → metrics.jsonl turn entries have "skill":"manual" and
#     skill-metrics.jsonl is NOT created.
#   - After register → turn events carry "skill":"wixie:converge" and skill-metrics.jsonl
#     contains a rich Atuin-style row with scope_id, session_id, repo_id, worktree.
#   - After unregister → new turn events revert to "manual".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"
SKILL_SCOPE="${REPO_ROOT}/shared/scripts/skill-scope.sh"
STATE_DIR="${REPO_ROOT}/plugins/context-guard/state"

# Use an isolated state dir so we don't step on developer's live data.
ISO_DIR=$(mktemp -d)
export FAE_ACTIVE_SKILLS_DIR="$ISO_DIR/active-skills"

cleanup() {
  rm -rf "$ISO_DIR" 2>/dev/null || true
  rm -f "${STATE_DIR}/metrics.jsonl" "${STATE_DIR}/skill-metrics.jsonl" 2>/dev/null || true
  rm -rf "${STATE_DIR}/metrics.jsonl.lock" "${STATE_DIR}/skill-metrics.jsonl.lock" 2>/dev/null || true
  [[ -n "${TF:-}" ]] && rm -f "$TF" 2>/dev/null
  [[ -n "${MT:-}" ]] && rm -f "$MT" 2>/dev/null
  [[ -n "${SH:-}" ]] && rm -f "/tmp/fae-drift-${SH}.jsonl" "/tmp/fae-drift-cooldown-${SH}" 2>/dev/null
}
trap cleanup EXIT

rm -f "${STATE_DIR}/metrics.jsonl" "${STATE_DIR}/skill-metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock" "${STATE_DIR}/skill-metrics.jsonl.lock"

TF=$(mktemp)
echo "attribution test" > "$TF"
MT=$(mktemp)
echo '{"role":"user","content":"x"}' > "$MT"
SH=$(md5sum "$MT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/fae-drift-${SH}.jsonl" "/tmp/fae-drift-cooldown-${SH}"

INPUT=$(jq -n --arg t "$MT" --arg f "$TF" '{transcript_path:$t, cwd:"/tmp", tool_name:"Read", tool_input:{file_path:$f}, tool_result:{content:"hi"}, hook_event_name:"PostToolUse"}')

# ── 1. Fire hook with no skill registered → manual ──
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true

if [[ ! -f "${STATE_DIR}/metrics.jsonl" ]]; then
  echo "FAIL: metrics.jsonl not created"
  exit 1
fi

SKILL_VAL=$(grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | head -1 | jq -r '.skill // empty' 2>/dev/null)
if [[ "$SKILL_VAL" != "manual" ]]; then
  echo "FAIL: expected skill=manual before register, got '$SKILL_VAL'"
  exit 1
fi

if [[ -f "${STATE_DIR}/skill-metrics.jsonl" ]]; then
  echo "FAIL: skill-metrics.jsonl must not exist when no skill is active"
  exit 1
fi

# ── 2. Register skill and fire hook → attributed ──
bash "$SKILL_SCOPE" register wixie:converge wixie >/dev/null

printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true

# The new turn row should have skill=wixie:converge
SKILL_VAL=$(grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | tail -1 | jq -r '.skill // empty' 2>/dev/null)
if [[ "$SKILL_VAL" != "wixie:converge" ]]; then
  echo "FAIL: expected skill=wixie:converge after register, got '$SKILL_VAL'"
  exit 1
fi

if [[ ! -f "${STATE_DIR}/skill-metrics.jsonl" ]]; then
  echo "FAIL: skill-metrics.jsonl should exist after skill-attributed call"
  exit 1
fi

# Verify required fields in the skill-metrics row
ROW=$(tail -1 "${STATE_DIR}/skill-metrics.jsonl")
for field in ts session_id repo_id worktree skill plugin scope_id tool token_estimate; do
  VAL=$(printf "%s" "$ROW" | jq -r ".${field} // empty" 2>/dev/null)
  if [[ -z "$VAL" ]] && [[ "$field" != "parent_scope_id" ]]; then
    echo "FAIL: skill-metrics row missing field '$field' (row: $ROW)"
    exit 1
  fi
done

# scope_id should be a 16-hex-char invocation id
SCOPE_ID=$(printf "%s" "$ROW" | jq -r '.scope_id')
if [[ ! "$SCOPE_ID" =~ ^[0-9a-f]{16}$ ]]; then
  echo "FAIL: scope_id '$SCOPE_ID' is not a 16-hex-char invocation id"
  exit 1
fi

# plugin field should be populated
PLUGIN_VAL=$(printf "%s" "$ROW" | jq -r '.plugin')
if [[ "$PLUGIN_VAL" != "wixie" ]]; then
  echo "FAIL: expected plugin=wixie, got '$PLUGIN_VAL'"
  exit 1
fi

# ── 3. Unregister → future calls revert to manual ──
bash "$SKILL_SCOPE" unregister wixie:converge >/dev/null

printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || true
SKILL_VAL=$(grep '"event":"turn"' "${STATE_DIR}/metrics.jsonl" | tail -1 | jq -r '.skill // empty' 2>/dev/null)
if [[ "$SKILL_VAL" != "manual" ]]; then
  echo "FAIL: expected skill=manual after unregister, got '$SKILL_VAL'"
  exit 1
fi

exit 0
