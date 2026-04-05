#!/usr/bin/env bash
# token-saver: PreToolUse hook for Read commands
# Blocks duplicate file reads within a session (TTL-based).
# Exit 2 = intentional block. Exit 0 on all errors (spec rule #6).

trap 'exit 0' INT TERM

set +e

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
HOOK_TOOL_INPUT=$(printf "%s" "$HOOK_INPUT" | jq -c '.tool_input // empty' 2>/dev/null)

if [[ -z "$HOOK_TOOL_INPUT" ]] || [[ "$HOOK_TOOL_INPUT" == "null" ]]; then
  exit 0
fi

# ── Extract and sanitize file path ──
FILE_PATH=$(printf "%s" "$HOOK_TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Block path traversal (spec rule #9)
DECODED=$(printf "%s" "$FILE_PATH" \
  | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')
if [[ "$DECODED" == *".."* ]]; then
  exit 0
fi

# ── Session hash (spec rule #2) ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── Cache file ──
CACHE_FILE="/tmp/allay-reads-${SESSION_HASH}.jsonl"

# ── Compute current file hash ──
CURRENT_HASH=""
if [[ -f "$FILE_PATH" ]]; then
  CURRENT_HASH=$(sha256sum "$FILE_PATH" 2>/dev/null | cut -c1-16 || true)
fi

# ── Check cache for duplicate ──
NOW=$(date +%s)

if [[ -f "$CACHE_FILE" ]]; then
  # Find most recent entry for this file (spec rule #4 — grep pre-filter, never jq -s)
  LAST_ENTRY=$(grep -F "\"$FILE_PATH\"" "$CACHE_FILE" 2>/dev/null | tail -1 || true)

  if [[ -n "$LAST_ENTRY" ]]; then
    LAST_HASH=$(printf "%s" "$LAST_ENTRY" | jq -r '.hash // empty' 2>/dev/null)
    LAST_TS=$(printf "%s" "$LAST_ENTRY" | jq -r '.ts // "0"' 2>/dev/null)
    ELAPSED=$(( NOW - LAST_TS ))

    # Block if: same hash AND within TTL
    if [[ "$CURRENT_HASH" == "$LAST_HASH" ]] && [[ "$ELAPSED" -lt "$ALLAY_DUPLICATE_TTL_SECONDS" ]]; then
      # Get preview (first 3 lines)
      PREVIEW=""
      if [[ -f "$FILE_PATH" ]]; then
        PREVIEW=$(head -n 3 "$FILE_PATH" 2>/dev/null | tr '\n' ' ' | cut -c1-120 || true)
      fi

      # Log blocked duplicate
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      METRIC=$(jq -cn \
        --arg event "duplicate_blocked" \
        --arg ts "$TIMESTAMP" \
        --arg file "$FILE_PATH" \
        '{event: $event, ts: $ts, file: $file}')
      STATE_DIR="${PLUGIN_ROOT}/state"
      log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

      # Block with exit 2 + stderr message
      printf "File %s read %ds ago. Unchanged. Preview: %s. Prefix FULL: to force." \
        "$FILE_PATH" "$ELAPSED" "$PREVIEW" >&2
      exit 2
    fi
  fi
fi

# ── Record this read in cache ──
ENTRY=$(jq -cn \
  --arg file "$FILE_PATH" \
  --arg hash "$CURRENT_HASH" \
  --argjson ts "$NOW" \
  '{file: $file, hash: $hash, ts: $ts}')

printf "%s\n" "$ENTRY" >> "$CACHE_FILE"

exit 0
