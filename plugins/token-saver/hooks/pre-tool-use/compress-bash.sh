#!/usr/bin/env bash
# token-saver: PreToolUse hook for Bash commands
# Compresses verbose tool outputs to reduce token usage.
# MUST exit 0 always (spec rule #6).


# Subagent recursion guard — see shared/conduct/hooks.md
if [[ -n "${CLAUDE_SUBAGENT:-}" ]]; then exit 0; fi

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

# Test runners (JS) → tail last 40 lines
if printf "%s" "$COMMAND" | grep -qE '^(npm|yarn|pnpm)\s+test|^vitest|^jest'; then
  NEW_COMMAND="${COMMAND} 2>&1 | tail -n 40"
  RULE="test_tail"

# Python test runners → strip to pass/fail summary
elif printf "%s" "$COMMAND" | grep -qE '^python\s+-m\s+(pytest|unittest)|^pytest'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(PASSED|FAILED|ERROR|passed|failed|error|warnings? summary|short test summary)' | tail -n 30"
  RULE="pytest_filter"

# Go test → strip to PASS/FAIL lines
elif printf "%s" "$COMMAND" | grep -qE '^go\s+test'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(^ok|^FAIL|^---|PASS|FAIL|panic)' | tail -n 30"
  RULE="gotest_filter"

# Maven/Gradle test → BUILD SUCCESS/FAILURE + test summary
elif printf "%s" "$COMMAND" | grep -qE '^(mvn|gradle|./gradlew)\s+test'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(BUILD |Tests run:|Test .*FAILED|> Task)' | tail -n 20"
  RULE="jvm_test_filter"

# .NET build/test → pass/fail summary
elif printf "%s" "$COMMAND" | grep -qE '^dotnet\s+(build|test)'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(Build succeeded|Build FAILED|Passed|Failed|Error\(s\)|Warning\(s\)|Test Run)' | tail -n 20"
  RULE="dotnet_filter"

# Package install → filter errors/warnings
elif printf "%s" "$COMMAND" | grep -qE '^(npm|yarn|pnpm)\s+install|^yarn$'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(ERR|WARN|error|warning|added|removed)' | tail -n 20"
  RULE="install_filter"

# Cargo build/test → filter errors/warnings
elif printf "%s" "$COMMAND" | grep -qE '^cargo\s+(build|test)'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(error|warning|test result)' | tail -n 30"
  RULE="cargo_filter"

# make / make build → strip to error lines or success
elif printf "%s" "$COMMAND" | grep -qE '^make(\s+\w+)?$'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(Error|error|warning|make:|\*\*\*)' || echo 'Build succeeded'; tail -n 20"
  RULE="make_filter"

# docker build → layer summaries and final image ID
elif printf "%s" "$COMMAND" | grep -qE '^docker\s+build'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(^Step |^Successfully |^#[0-9]+ |ERROR|error)' | tail -n 30"
  RULE="docker_build_filter"

# terraform plan → strip to summary
elif printf "%s" "$COMMAND" | grep -qE '^terraform\s+plan'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(Plan:|No changes|Error)' | tail -n 10"
  RULE="terraform_plan_filter"

# eslint → error count and first errors
elif printf "%s" "$COMMAND" | grep -qE '^(eslint|npx eslint)'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(✖|error|warning|problems)' | head -n 20"
  RULE="eslint_filter"

# tsc (TypeScript compiler) → error count and first errors
elif printf "%s" "$COMMAND" | grep -qE '^(tsc|npx tsc)'; then
  NEW_COMMAND="${COMMAND} 2>&1 | grep -E '(error TS|Found [0-9])' | head -n 20"
  RULE="tsc_filter"

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
  # Bug fix: use jq -n for safe JSON construction (no printf/sed fragility)
  jq -n --arg cmd "$NEW_COMMAND" '{"hookSpecificOutput":{"updatedInput":{"command":$cmd}}}'

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
