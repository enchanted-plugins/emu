#!/usr/bin/env bash
# context-guard: PostToolUse hook
# Detects drift patterns: read loops, edit-revert cycles, test fail loops.
# Fires on EVERY tool call — must be fast.
# MUST exit 0 always (spec rule #6).

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

# ── Read hook input from stdin ──
HOOK_INPUT=$(cat)

if ! validate_json "$HOOK_INPUT"; then
  exit 0
fi

HOOK_TRANSCRIPT_PATH=$(printf "%s" "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TOOL_NAME=$(printf "%s" "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(printf "%s" "$HOOK_INPUT" | jq -c '.tool_input // {}' 2>/dev/null)

if [[ -z "$TOOL_NAME" ]]; then
  exit 0
fi

# ── Session hash (spec rule #2) ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── Session cache and cooldown files ──
CACHE_FILE="/tmp/allay-drift-${SESSION_HASH}.jsonl"
COOLDOWN_FILE="/tmp/allay-drift-cooldown-${SESSION_HASH}"
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
  Read)
    FILE_PATH=$(printf "%s" "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
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
    exit 0
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

# ── Cooldown check: max 1 alert per N turns ──
LAST_ALERT_TURN=0
if [[ -f "$COOLDOWN_FILE" ]]; then
  LAST_ALERT_TURN=$(cat "$COOLDOWN_FILE" 2>/dev/null | tr -d '[:space:]')
  LAST_ALERT_TURN=${LAST_ALERT_TURN:-0}
fi

# Only apply cooldown if an alert was actually fired before (LAST_ALERT_TURN > 0)
if [[ "$LAST_ALERT_TURN" -gt 0 ]] && [[ $((TURN - LAST_ALERT_TURN)) -lt "$ALLAY_DRIFT_COOLDOWN_TURNS" ]]; then
  exit 0
fi

# ── Pattern detection (only check the relevant pattern for the tool type) ──
ALERT_MSG=""
DRIFT_PATTERN=""

case "$TOOL_NAME" in
  Read)
    # ── Pattern 1: Read Loop ──
    # Same file read N+ times without a Write that changes its hash
    if [[ -n "$FILE_PATH" ]]; then
      # Count reads of this file (grep -F for fixed-string, wc -l for count)
      READ_COUNT=$(grep -F "\"tool\":\"Read\"" "$CACHE_FILE" 2>/dev/null \
        | grep -F "\"$FILE_PATH\"" 2>/dev/null \
        | wc -l | tr -d '[:space:]')
      READ_COUNT=${READ_COUNT:-0}

      if [[ "$READ_COUNT" -ge "$ALLAY_DRIFT_READ_THRESHOLD" ]]; then
        # Check if there's a Write with a DIFFERENT hash since the first Read
        WRITE_WITH_CHANGE=$(grep -E '"tool":"(Write|Edit)"' "$CACHE_FILE" 2>/dev/null \
          | grep -F "\"$FILE_PATH\"" 2>/dev/null \
          | grep -v -F "\"hash\":\"${FILE_HASH}\"" 2>/dev/null \
          | wc -l | tr -d '[:space:]')
        WRITE_WITH_CHANGE=${WRITE_WITH_CHANGE:-0}

        if [[ "$WRITE_WITH_CHANGE" -eq 0 ]]; then
          DRIFT_PATTERN="read_loop"
          ALERT_MSG="Drift Alert: ${FILE_PATH} read ${READ_COUNT}x without changes. Claude may be stuck re-reading without progress. → Reframe the problem or /allay:checkpoint before /compact."
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
      # Count consecutive failures of same cmd_base from end of cache
      # Use tail + reverse approach (portable, no tac dependency)
      FAIL_COUNT=0
      REVERSED=$(tail -n 20 "$CACHE_FILE" 2>/dev/null | sed '1!G;h;$!d')
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        LINE_TOOL=$(printf "%s" "$line" | jq -r '.tool // empty' 2>/dev/null)
        LINE_CMD=$(printf "%s" "$line" | jq -r '.cmd_base // empty' 2>/dev/null)
        LINE_EXIT=$(printf "%s" "$line" | jq -r '.exit // "0"' 2>/dev/null)

        if [[ "$LINE_TOOL" == "Bash" ]] && [[ "$LINE_CMD" == "$CMD_BASE" ]] && [[ "$LINE_EXIT" != "0" ]]; then
          FAIL_COUNT=$((FAIL_COUNT + 1))
        else
          if [[ "$LINE_TOOL" == "Bash" ]]; then
            break
          fi
        fi
      done <<< "$REVERSED"

      if [[ "$FAIL_COUNT" -ge "$ALLAY_DRIFT_FAIL_THRESHOLD" ]]; then
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
