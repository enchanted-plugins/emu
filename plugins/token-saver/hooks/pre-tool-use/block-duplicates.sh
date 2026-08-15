#!/usr/bin/env bash
# token-saver: PreToolUse hook for Read commands
# Detects duplicate file reads within a session (TTL-based) and emits a stderr advisory.
# Delta mode: if file changed since last read, emits a diff advisory.
# Advisory contract per shared/conduct/hooks.md — never block, never exit non-zero.
# Caching is best-effort; the underlying Read still proceeds. May be re-architected as a
# user-invoked Skill in a future revision (see plugin README).


# Subagent recursion guard — see shared/conduct/hooks.md
if [[ -n "${CLAUDE_SUBAGENT:-}" ]]; then exit 0; fi

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

# ── Session hash ──
# Stable per-session key. Do NOT hash the transcript file *contents*: it grows
# every turn, so the key changed on every call and the read-dedup cache was
# reborn empty each time (VF-04). Key off the stable session_id from the
# payload; fall back to the transcript *path* string, then pid.
EMU_SESSION_KEY=$(printf "%s" "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
EMU_SESSION_KEY="${EMU_SESSION_KEY:-${EMU_SESSION_ID:-${HOOK_TRANSCRIPT_PATH:-pid-$$}}}"
SESSION_HASH=$(printf "%s" "$EMU_SESSION_KEY" | md5sum 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── Cache file ──
CACHE_FILE="/tmp/emu-reads-${SESSION_HASH}.jsonl"

# ── Delta mode cache directory ──
DELTA_CACHE_DIR="/tmp/emu-delta-${SESSION_HASH}"
mkdir -p "$DELTA_CACHE_DIR" 2>/dev/null || true

# ── Compute current file hash ──
CURRENT_HASH=""
if [[ -f "$FILE_PATH" ]]; then
  CURRENT_HASH=$(sha256sum "$FILE_PATH" 2>/dev/null | cut -c1-16 || true)
fi

# Skip delta/dedup for empty content (edge case)
if [[ -z "$CURRENT_HASH" ]]; then
  # File doesn't exist or is empty — treat as fresh read, don't cache
  exit 0
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

    if [[ "$ELAPSED" -lt "$EMU_DUPLICATE_TTL_SECONDS" ]]; then
      if [[ "$CURRENT_HASH" == "$LAST_HASH" ]]; then
        # ── BLOCK: Same hash, within TTL ──
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

        # Advisory: would have blocked, but we let Read proceed per hooks.md contract.
        {
          echo "=== token-saver (advisory) ==="
          echo "Would have blocked: duplicate Read of $FILE_PATH within ${ELAPSED}s TTL (unchanged)."
          echo "Preview: $PREVIEW"
          echo "Hint: prefix the path with FULL: to suppress this advisory in the future."
        } >&2
        exit 0

      else
        # ── DELTA MODE: File changed since last read — return diff only ──
        # Hash the file path to create a safe cache filename
        CACHE_KEY=$(printf "%s" "$FILE_PATH" | md5sum 2>/dev/null | cut -c1-16 || echo "unknown")
        CACHED_COPY="${DELTA_CACHE_DIR}/${CACHE_KEY}"

        if [[ -f "$CACHED_COPY" ]] && command -v diff >/dev/null 2>&1; then
          # Generate unified diff with 3 lines of context
          DIFF_OUTPUT=$(diff -u --label "previous" --label "current" "$CACHED_COPY" "$FILE_PATH" 2>/dev/null || true)

          if [[ -n "$DIFF_OUTPUT" ]]; then
            DIFF_LINES=$(printf "%s" "$DIFF_OUTPUT" | wc -l | tr -d ' ')
            FILE_LINES=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')

            # Only use delta if diff is significantly smaller than full file
            if [[ "$DIFF_LINES" -lt $((FILE_LINES / 2)) ]]; then
              # Log delta mode usage
              TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
              METRIC=$(jq -cn \
                --arg event "delta_read" \
                --arg ts "$TIMESTAMP" \
                --arg file "$FILE_PATH" \
                --argjson full_lines "$FILE_LINES" \
                --argjson diff_lines "$DIFF_LINES" \
                '{event: $event, ts: $ts, file: $file, full_lines: $full_lines, diff_lines: $diff_lines}')
              STATE_DIR="${PLUGIN_ROOT}/state"
              log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

              # Update cached copy for next comparison
              cp "$FILE_PATH" "$CACHED_COPY" 2>/dev/null || true

              # Update cache entry
              ENTRY=$(jq -cn \
                --arg file "$FILE_PATH" \
                --arg hash "$CURRENT_HASH" \
                --argjson ts "$NOW" \
                '{file: $file, hash: $hash, ts: $ts}')
              printf "%s\n" "$ENTRY" >> "$CACHE_FILE"

              # Output delta as stderr info (file will still be read, but user sees the note)
              printf "Delta mode: %s changed (%d lines diff vs %d total). Showing changes only:\n%s" \
                "$FILE_PATH" "$DIFF_LINES" "$FILE_LINES" "$DIFF_OUTPUT" >&2
              # Let the read proceed — delta is informational
              exit 0
            fi
          fi
        fi

        # Cache current version for future delta comparisons
        cp "$FILE_PATH" "$CACHED_COPY" 2>/dev/null || true
      fi
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

# ── Cache file content for future delta comparisons ──
CACHE_KEY=$(printf "%s" "$FILE_PATH" | md5sum 2>/dev/null | cut -c1-16 || echo "unknown")
CACHED_COPY="${DELTA_CACHE_DIR}/${CACHE_KEY}"
cp "$FILE_PATH" "$CACHED_COPY" 2>/dev/null || true

exit 0
