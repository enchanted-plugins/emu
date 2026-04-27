#!/usr/bin/env bash
# context-guard: PostToolUse hook
# Detects drift patterns: read loops, edit-revert cycles, test fail loops.
# Estimates token usage per tool call for runway/analytics.
# Fires on EVERY tool call — must be fast.
# MUST exit 0 always (spec rule #6).


# Subagent recursion guard — see shared/conduct/hooks.md
if [[ -n "${CLAUDE_SUBAGENT:-}" ]]; then exit 0; fi

trap 'exit 0' ERR INT TERM

# ── Check jq availability (graceful without jq) ──
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Resolve paths
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SHARED_DIR="${PLUGIN_ROOT}/../../shared"

# shellcheck source=../../../../shared/constants.sh
source "${SHARED_DIR}/constants.sh"
# shellcheck source=../../../../shared/sanitize.sh
source "${SHARED_DIR}/sanitize.sh"
# shellcheck source=../../../../shared/metrics.sh
source "${SHARED_DIR}/metrics.sh"
# A9 — resolve repo_id, worktree, session_id, global XDG dirs.
# Sourced (not invoked) so exports propagate into this shell.
export EMU_PLUGIN_STATE_DIR="${PLUGIN_ROOT}/state"
# shellcheck source=../../../../shared/scripts/session-init.sh
source "${SHARED_DIR}/scripts/session-init.sh" || true

# ── Read hook input from stdin ──
HOOK_INPUT=$(cat)

if ! validate_json "$HOOK_INPUT"; then
  exit 0
fi

HOOK_TRANSCRIPT_PATH=$(printf "%s" "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TOOL_NAME=$(printf "%s" "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(printf "%s" "$HOOK_INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
TOOL_RESULT=$(printf "%s" "$HOOK_INPUT" | jq -c '.tool_result // {}' 2>/dev/null)

if [[ -z "$TOOL_NAME" ]]; then
  exit 0
fi

# ── Session hash (spec rule #2) ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── A8 — Skill-Scoped Attribution ──
# Resolve the currently-active skill scope (or "manual" if none).
# current-env returns key=value lines we consume via a subshell parse.
ACTIVE_SKILL="manual"
ACTIVE_PLUGIN=""
ACTIVE_SCOPE_ID=""
ACTIVE_SCOPE_PARENT=""
ACTIVE_SCOPE_DEPTH="0"
SKILL_SCOPE_SCRIPT="${SHARED_DIR}/scripts/skill-scope.sh"
if [[ -x "$SKILL_SCOPE_SCRIPT" ]] || [[ -f "$SKILL_SCOPE_SCRIPT" ]]; then
  while IFS='=' read -r _k _v; do
    _v="${_v%$'\r'}"  # defensive: strip CR if any producer leaked it
    case "$_k" in
      EMU_SCOPE_SKILL)  ACTIVE_SKILL="${_v:-manual}" ;;
      EMU_SCOPE_PLUGIN) ACTIVE_PLUGIN="$_v" ;;
      EMU_SCOPE_ID)     ACTIVE_SCOPE_ID="$_v" ;;
      EMU_SCOPE_PARENT) ACTIVE_SCOPE_PARENT="$_v" ;;
      EMU_SCOPE_DEPTH)  ACTIVE_SCOPE_DEPTH="${_v:-0}" ;;
    esac
  done < <(bash "$SKILL_SCOPE_SCRIPT" current-env 2>/dev/null || true)
fi
[[ -z "$ACTIVE_SKILL" ]] && ACTIVE_SKILL="manual"

# ── Session cache and cooldown files ──
CACHE_FILE="/tmp/emu-drift-${SESSION_HASH}.jsonl"
COOLDOWN_FILE="/tmp/emu-drift-cooldown-${SESSION_HASH}"
STATE_DIR="${PLUGIN_ROOT}/state"

# Create cache if missing
touch "$CACHE_FILE" 2>/dev/null || exit 0

# ── Extract tool-specific data ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILE_PATH=""
FILE_HASH=""
CMD_BASE=""
EXIT_CODE=""

case "$TOOL_NAME" in
  Read|Glob|Grep)
    FILE_PATH=$(printf "%s" "$TOOL_INPUT" | jq -r '.file_path // .path // .pattern // empty' 2>/dev/null)
    # Sanitize path (spec rule #9)
    if [[ -n "$FILE_PATH" ]]; then
      DECODED=$(printf "%s" "$FILE_PATH" | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')
      if [[ "$DECODED" == *".."* ]]; then exit 0; fi
      # Compute hash
      if [[ -f "$FILE_PATH" ]]; then
        FILE_HASH=$(sha256sum "$FILE_PATH" 2>/dev/null | cut -c1-16 || true)
      fi
    fi
    ;;
  Write|Edit|MultiEdit)
    FILE_PATH=$(printf "%s" "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
    if [[ -n "$FILE_PATH" ]]; then
      DECODED=$(printf "%s" "$FILE_PATH" | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')
      if [[ "$DECODED" == *".."* ]]; then exit 0; fi
      if [[ -f "$FILE_PATH" ]]; then
        FILE_HASH=$(sha256sum "$FILE_PATH" 2>/dev/null | cut -c1-16 || true)
      fi
    fi
    ;;
  Bash)
    FULL_CMD=$(printf "%s" "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
    # Log cmd_base only — first 2 words (spec security: never full command)
    CMD_BASE=$(printf "%s" "$FULL_CMD" | awk '{print $1, $2}' | head -c 60)
    # Extract exit code from tool result
    EXIT_CODE=$(printf "%s" "$HOOK_INPUT" | jq -r '.tool_result.exit_code // empty' 2>/dev/null)
    if [[ -z "$EXIT_CODE" ]]; then
      EXIT_CODE=$(printf "%s" "$HOOK_INPUT" | jq -r '.exit_code // "0"' 2>/dev/null)
    fi
    ;;
  *)
    # Still log token estimation for unknown tools, but no drift detection
    ;;
esac

# ── Determine current turn number ──
TURN=$(wc -l < "$CACHE_FILE" 2>/dev/null | tr -d '[:space:]')
TURN=${TURN:-0}
TURN=$((TURN + 1))

# ── Append to session cache ──
CACHE_ENTRY=$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg tool "$TOOL_NAME" \
  --arg file "$FILE_PATH" \
  --arg hash "$FILE_HASH" \
  --arg cmd_base "$CMD_BASE" \
  --arg exit_code "$EXIT_CODE" \
  --argjson turn "$TURN" \
  '{ts:$ts, tool:$tool, file:$file, hash:$hash, cmd_base:$cmd_base, exit:$exit_code, turn:$turn}')

printf "%s\n" "$CACHE_ENTRY" >> "$CACHE_FILE"

# ── Token estimation (runway data fix) ──
# Estimate tokens from tool_input + tool_result byte sizes
# ~1.3 tokens per word, ~4 chars per word ≈ 0.325 tokens per char
INPUT_BYTES=${#TOOL_INPUT}
RESULT_BYTES=${#TOOL_RESULT}
EST_TOKENS=$(( (INPUT_BYTES + RESULT_BYTES) * 13 / 40 ))
# Minimum 50 tokens per call (overhead)
[[ "$EST_TOKENS" -lt 50 ]] && EST_TOKENS=50

TURN_METRIC=$(jq -cn \
  --arg event "turn" \
  --arg ts "$TIMESTAMP" \
  --arg tool "$TOOL_NAME" \
  --argjson tokens_est "$EST_TOKENS" \
  --argjson turn "$TURN" \
  --arg skill "$ACTIVE_SKILL" \
  '{event:$event, ts:$ts, tool:$tool, tokens_est:$tokens_est, turn:$turn, skill:$skill}')

log_metric "${STATE_DIR}/metrics.jsonl" "$TURN_METRIC"

# ── A8/A9 — Skill-scoped + cross-worktree attribution ──
# Row schema matches Atuin's event model so GROUP BY works cheaply on read:
#   {ts, session_id, repo_id, worktree, cwd, host, skill, plugin, scope_id,
#    parent_scope_id, depth, tool, token_estimate}
SKILL_ROW=$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg session_id "${EMU_SESSION_ID:-}" \
  --arg repo_id "${EMU_REPO_ID:-}" \
  --arg worktree "${EMU_WORKTREE_REL:-.}" \
  --arg worktree_path "${EMU_WORKTREE_PATH:-}" \
  --arg cwd "${HOOK_CWD:-$PWD}" \
  --arg host "${EMU_HOST:-}" \
  --arg skill "$ACTIVE_SKILL" \
  --arg plugin "$ACTIVE_PLUGIN" \
  --arg scope_id "$ACTIVE_SCOPE_ID" \
  --arg parent_scope_id "$ACTIVE_SCOPE_PARENT" \
  --argjson depth "${ACTIVE_SCOPE_DEPTH:-0}" \
  --arg tool "$TOOL_NAME" \
  --argjson token_estimate "$EST_TOKENS" \
  '{ts:$ts, session_id:$session_id, repo_id:$repo_id, worktree:$worktree,
    worktree_path:$worktree_path, cwd:$cwd, host:$host,
    skill:$skill, plugin:$plugin, scope_id:$scope_id,
    parent_scope_id:$parent_scope_id, depth:$depth,
    tool:$tool, token_estimate:$token_estimate}')

# Local skill-metrics (only meaningful when a skill is active).
if [[ "$ACTIVE_SKILL" != "manual" ]]; then
  log_metric "${STATE_DIR}/skill-metrics.jsonl" "$SKILL_ROW"
fi

# Global cross-worktree shard. Per-PID filename avoids concurrent-append
# interleaving on filesystems without append-atomicity (Windows, NFS).
# Readers glob all *.jsonl shards under the repo_id dir and sort by ts.
if [[ -n "${EMU_GLOBAL_STATE_DIR:-}" ]]; then
  mkdir -p "$EMU_GLOBAL_STATE_DIR" 2>/dev/null || true
  GLOBAL_SHARD="${EMU_GLOBAL_STATE_DIR}/skill-metrics-global.$$.jsonl"
  # Rotate at 10MB (matches EMU_MAX_METRICS_BYTES).
  if [[ -f "$GLOBAL_SHARD" ]]; then
    _g_size=$(wc -c < "$GLOBAL_SHARD" 2>/dev/null | tr -d ' ')
    if [[ "${_g_size:-0}" -gt "${EMU_MAX_METRICS_BYTES:-10485760}" ]]; then
      tail -n 1000 "$GLOBAL_SHARD" > "${GLOBAL_SHARD}.rot" 2>/dev/null \
        && mv "${GLOBAL_SHARD}.rot" "$GLOBAL_SHARD"
    fi
    unset _g_size
  fi
  # One write() per line — small rows (<4KB) append atomically on Linux/ext4
  # and are exclusive-per-PID on Windows, so no cross-process lock needed.
  printf "%s\n" "$SKILL_ROW" >> "$GLOBAL_SHARD" 2>/dev/null || true
fi

# ── Cooldown check: max 1 alert per N turns ──
LAST_ALERT_TURN=0
if [[ -f "$COOLDOWN_FILE" ]]; then
  LAST_ALERT_TURN=$(cat "$COOLDOWN_FILE" 2>/dev/null | tr -d '[:space:]')
  LAST_ALERT_TURN=${LAST_ALERT_TURN:-0}
fi

# Only apply cooldown if an alert was actually fired before (LAST_ALERT_TURN > 0)
if [[ "$LAST_ALERT_TURN" -gt 0 ]] && [[ $((TURN - LAST_ALERT_TURN)) -lt "$EMU_DRIFT_COOLDOWN_TURNS" ]]; then
  exit 0
fi

# ── Pattern detection (only check the relevant pattern for the tool type) ──
ALERT_MSG=""
DRIFT_PATTERN=""

case "$TOOL_NAME" in
  Read|Glob|Grep)
    # ── Pattern 1: Read Loop ──
    # Same file/pattern accessed N+ times without a Write that changes its hash
    if [[ -n "$FILE_PATH" ]]; then
      # Count reads of this file (grep -F for fixed-string, wc -l for count)
      READ_COUNT=$(grep -F "\"tool\":\"${TOOL_NAME}\"" "$CACHE_FILE" 2>/dev/null \
        | grep -F "\"$FILE_PATH\"" 2>/dev/null \
        | wc -l | tr -d '[:space:]')
      READ_COUNT=${READ_COUNT:-0}

      if [[ "$READ_COUNT" -ge "$EMU_DRIFT_READ_THRESHOLD" ]]; then
        # Check if there's a Write with a DIFFERENT hash since the first Read
        WRITE_WITH_CHANGE=$(grep -E '"tool":"(Write|Edit)"' "$CACHE_FILE" 2>/dev/null \
          | grep -F "\"$FILE_PATH\"" 2>/dev/null \
          | grep -v -F "\"hash\":\"${FILE_HASH}\"" 2>/dev/null \
          | wc -l | tr -d '[:space:]')
        WRITE_WITH_CHANGE=${WRITE_WITH_CHANGE:-0}

        if [[ "$WRITE_WITH_CHANGE" -eq 0 ]]; then
          DRIFT_PATTERN="read_loop"
          ALERT_MSG="Drift Alert: ${FILE_PATH} read ${READ_COUNT}x without changes. Claude may be stuck re-reading without progress. → Reframe the problem or /emu:checkpoint before /compact."
        fi
      fi
    fi
    ;;

  Write|Edit|MultiEdit)
    # ── Pattern 2: Edit-Revert Cycle ──
    # File written to a hash matching a previous version
    if [[ -n "$FILE_PATH" ]] && [[ -n "$FILE_HASH" ]]; then
      # Count previous writes to this file with the SAME hash
      REVERT_COUNT=$(grep -E '"tool":"(Write|Edit|MultiEdit)"' "$CACHE_FILE" 2>/dev/null \
        | grep -F "\"$FILE_PATH\"" 2>/dev/null \
        | grep -F "\"hash\":\"${FILE_HASH}\"" 2>/dev/null \
        | wc -l | tr -d '[:space:]')
      REVERT_COUNT=${REVERT_COUNT:-0}

      # Subtract 1 for the entry we just appended
      REVERT_COUNT=$((REVERT_COUNT - 1))

      if [[ "$REVERT_COUNT" -ge 1 ]]; then
        DRIFT_PATTERN="edit_revert"
        ALERT_MSG="Drift Alert: ${FILE_PATH} reverted to previous state ${REVERT_COUNT}x. Claude is oscillating between approaches. → Pick one approach and commit to it."
      fi
    fi
    ;;

  Bash)
    # ── Pattern 3: Test Fail Loop ──
    # Same base command fails N+ times consecutively
    if [[ -n "$EXIT_CODE" ]] && [[ "$EXIT_CODE" != "0" ]] && [[ -n "$CMD_BASE" ]]; then
      # Bug fix: process bounded tail with single jq -s call instead of per-line jq
      REVERSED_JSON=$(tail -n 20 "$CACHE_FILE" 2>/dev/null | jq -s 'reverse' 2>/dev/null)
      FAIL_COUNT=0

      if [[ -n "$REVERSED_JSON" ]] && [[ "$REVERSED_JSON" != "null" ]]; then
        FAIL_COUNT=$(printf "%s" "$REVERSED_JSON" | jq --arg cmd "$CMD_BASE" '
          [.[] | select(.tool == "Bash")] |
          reduce .[] as $entry (
            {count: 0, done: false};
            if .done then .
            elif ($entry.cmd_base == $cmd and $entry.exit != "0" and $entry.exit != "") then .count += 1
            else .done = true
            end
          ) | .count
        ' 2>/dev/null)
        FAIL_COUNT=${FAIL_COUNT:-0}
      fi

      if [[ "$FAIL_COUNT" -ge "$EMU_DRIFT_FAIL_THRESHOLD" ]]; then
        DRIFT_PATTERN="test_fail_loop"
        ALERT_MSG="Drift Alert: '${CMD_BASE}' failed ${FAIL_COUNT}x this session. Retrying without changes won't help. → Read the error, change the approach."
      fi
    fi
    ;;
esac

# ── Fire alert if detected ──
if [[ -n "$ALERT_MSG" ]]; then
  # Update cooldown
  printf "%s" "$TURN" > "$COOLDOWN_FILE"

  # Alert via stderr (always exit 0)
  printf "⚠️ %s" "$ALERT_MSG" >&2

  # Log detection metric
  METRIC=$(jq -cn \
    --arg event "drift_detected" \
    --arg ts "$TIMESTAMP" \
    --arg pattern "$DRIFT_PATTERN" \
    --arg file "$FILE_PATH" \
    --arg cmd "$CMD_BASE" \
    --argjson turn "$TURN" \
    '{event:$event, ts:$ts, pattern:$pattern, file:$file, cmd:$cmd, turn:$turn}')

  log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"
fi

exit 0
