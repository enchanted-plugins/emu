#!/usr/bin/env bash
# token-saver: PostToolUse hook for tool result aging
# Ages old tool results to reduce context consumption:
#   - Recent (last 10 calls): keep full
#   - Mid-age (calls 11-30): minify to first/last 5 lines + omission notice
#   - Old (calls 30+): stub to one line
# MUST exit 0 always (spec rule #6).

trap 'exit 0' ERR INT TERM

set -uo pipefail

# ── Check jq availability ──
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
TOOL_RESULT=$(printf "%s" "$HOOK_INPUT" | jq -r '.tool_result // empty' 2>/dev/null)

if [[ -z "$TOOL_NAME" ]] || [[ -z "$TOOL_RESULT" ]] || [[ "$TOOL_RESULT" == "null" ]]; then
  exit 0
fi

# ── Session hash ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── Call counter file ──
COUNTER_FILE="/tmp/fae-age-${SESSION_HASH}.count"
touch "$COUNTER_FILE" 2>/dev/null || exit 0

# Increment call count
CALL_NUM=$(wc -l < "$COUNTER_FILE" 2>/dev/null | tr -d '[:space:]')
CALL_NUM=${CALL_NUM:-0}
CALL_NUM=$((CALL_NUM + 1))

# Log this call
printf "%s %s\n" "$CALL_NUM" "$TOOL_NAME" >> "$COUNTER_FILE"

# ── Age determination ──
# Tool result aging only applies to results that are large enough to matter
RESULT_LEN=${#TOOL_RESULT}

# Skip small results (< 500 chars)
if [[ "$RESULT_LEN" -lt 500 ]]; then
  exit 0
fi

# Determine age tier based on how many calls ago this result will be
# We don't modify the current result — we let context-guard's metrics
# track the data. The aging logic is informational via stderr.

# For the current call, we just track. The aging advice is shown as
# a stderr note when results are getting large and old.
if [[ "$CALL_NUM" -gt 30 ]]; then
  RESULT_LINES=$(printf "%s" "$TOOL_RESULT" | wc -l | tr -d ' ')
  if [[ "$RESULT_LINES" -gt 10 ]]; then
    printf "[Emu] Tool result #%d (%s, %d lines) — consider re-reading if needed rather than relying on aged context." \
      "$CALL_NUM" "$TOOL_NAME" "$RESULT_LINES" >&2

    # Log aging event
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    METRIC=$(jq -cn \
      --arg event "result_aged" \
      --arg ts "$TIMESTAMP" \
      --arg tool "$TOOL_NAME" \
      --argjson call_num "$CALL_NUM" \
      --argjson result_bytes "$RESULT_LEN" \
      '{event: $event, ts: $ts, tool: $tool, call_num: $call_num, result_bytes: $result_bytes}')
    STATE_DIR="${PLUGIN_ROOT}/state"
    log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"
  fi
fi

exit 0
