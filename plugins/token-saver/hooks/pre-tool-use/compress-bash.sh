#!/usr/bin/env bash
# token-saver: PreToolUse hook for Bash commands
# Compresses verbose tool outputs to reduce token usage.
# MUST exit 0 always (spec rule #6).

trap 'exit 0' ERR INT TERM

set -uo pipefail

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

HOOK_TOOL_INPUT=$(printf "%s" "$HOOK_INPUT" | jq -c '.tool_input // empty' 2>/dev/null)

if [[ -z "$HOOK_TOOL_INPUT" ]] || [[ "$HOOK_TOOL_INPUT" == "null" ]]; then
  exit 0
fi

# Extract command string
COMMAND=$(printf "%s" "$HOOK_TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ── Skip conditions ──

# Skip if starts with FULL: (user bypass)
if [[ "$COMMAND" == FULL:* ]]; then
  exit 0
fi

# Skip if already piped (has | character outside quotes — simple heuristic)
if [[ "$COMMAND" == *" | "* ]]; then
  exit 0
fi

# Skip interactive commands
case "$COMMAND" in
  vim*|nano*|less*|top|htop|watch*|man\ *)
    exit 0 ;;
esac

# ── Apply compression rules ──
NEW_COMMAND=""
RULE=""

# Test runners → tail last 40 lines
if printf "%s" "$COMMAND" | grep -qE '^(npm|yarn|pnpm)\s+test|^vitest|^jest'; then
  NEW_COMMAND="${COMMAND} 2>&1 | tail -n 40"
  RULE="test_tail"

# Package install → filter errors/warnings
elif printf "%s" "$COMMAND" | grep -qE '^(npm|yarn|pnpm)\s+install|^yarn$'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(ERR|WARN|error|warning|added|removed)' | tail -n 20"
  RULE="install_filter"

# Cargo build/test → filter errors/warnings
elif printf "%s" "$COMMAND" | grep -qE '^cargo\s+(build|test)'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(error|warning|test result)' | tail -n 30"
  RULE="cargo_filter"

# git log without -n or --oneline → add --oneline -20
elif printf "%s" "$COMMAND" | grep -qE '^git\s+log'; then
  if ! printf "%s" "$COMMAND" | grep -qE '\-n\s|\-\-oneline'; then
    NEW_COMMAND=$(printf "%s" "$COMMAND" | sed 's/^git log/git log --oneline -20/')
    RULE="git_log_trim"
  fi

# find without head → add head
elif printf "%s" "$COMMAND" | grep -qE '^find\s'; then
  if ! printf "%s" "$COMMAND" | grep -q 'head'; then
    NEW_COMMAND="${COMMAND} | head -n 30"
    RULE="find_head"
  fi

# cat large file → head with line count
elif printf "%s" "$COMMAND" | grep -qE '^cat\s'; then
  FILE_ARG=$(printf "%s" "$COMMAND" | sed 's/^cat\s\+//' | sed 's/\s*$//')
  if [[ -f "$FILE_ARG" ]]; then
    LINE_COUNT=$(wc -l < "$FILE_ARG" 2>/dev/null | tr -d ' ')
    if [[ "$LINE_COUNT" -gt 100 ]]; then
      NEW_COMMAND="head -n 80 ${FILE_ARG} && echo '--- [${LINE_COUNT} lines total] ---'"
      RULE="cat_head"
    fi
  fi
fi

# ── Output modified command or exit silently ──
if [[ -n "$NEW_COMMAND" ]]; then
  # Output updatedInput JSON to stdout (spec rule #3 — 64KB limit)
  printf '{"hookSpecificOutput":{"updatedInput":{"command":"%s"}}}' \
    "$(printf "%s" "$NEW_COMMAND" | jq -Rs '.' | sed 's/^"//;s/"$//')"

  # Log compression
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  METRIC=$(jq -cn \
    --arg event "bash_compressed" \
    --arg ts "$TIMESTAMP" \
    --arg rule "$RULE" \
    '{event: $event, ts: $ts, rule: $rule}')

  STATE_DIR="${PLUGIN_ROOT}/state"
  log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"
fi

exit 0
