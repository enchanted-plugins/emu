#!/usr/bin/env bash
# state-keeper: PreCompact hook
# Saves checkpoint.md before compaction wipes context.
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

# ── Read hook input from stdin (real API sends JSON on stdin) ──
HOOK_INPUT=$(cat)

if ! validate_json "$HOOK_INPUT"; then
  exit 0
fi

HOOK_TRANSCRIPT_PATH=$(printf "%s" "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
HOOK_CWD=$(printf "%s" "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
HOOK_SESSION_ID=$(printf "%s" "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fallback CWD
HOOK_CWD="${HOOK_CWD:-$(pwd)}"

# ── Session hash (spec rule #2 — never use session_id for cache keys) ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── State directory ──
STATE_DIR="${PLUGIN_ROOT}/state"
CHECKPOINT_FILE="${STATE_DIR}/checkpoint.md"
CHECKPOINT_TMP="${CHECKPOINT_FILE}.tmp"
LOCK_DIR="${CHECKPOINT_FILE}${ALLAY_LOCK_SUFFIX}"

# ── Gather git info (graceful without git — skip sections, no error) ──
GIT_BRANCH=""
GIT_MODIFIED=""
GIT_STAGED=""
GIT_LOG=""

if command -v git >/dev/null 2>&1; then
  GIT_BRANCH=$(cd "$HOOK_CWD" && git branch --show-current 2>/dev/null || true)
  GIT_MODIFIED=$(cd "$HOOK_CWD" && git diff --name-only HEAD 2>/dev/null || true)
  GIT_STAGED=$(cd "$HOOK_CWD" && git diff --cached --name-only 2>/dev/null || true)
  GIT_LOG=$(cd "$HOOK_CWD" && git log --oneline -10 2>/dev/null || true)
fi

# ── Project instructions (first 50 lines of CLAUDE.md if exists) ──
PROJECT_INSTRUCTIONS=""
if [[ -f "${HOOK_CWD}/CLAUDE.md" ]]; then
  PROJECT_INSTRUCTIONS=$(head -n 50 "${HOOK_CWD}/CLAUDE.md" 2>/dev/null || true)
fi

# ── User-flagged context (state/remember.md if exists) ──
REMEMBER_CONTENT=""
if [[ -f "${STATE_DIR}/remember.md" ]]; then
  REMEMBER_CONTENT=$(cat "${STATE_DIR}/remember.md" 2>/dev/null || true)
fi

# ── Build checkpoint markdown ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

CHECKPOINT="# Allay Checkpoint
> Saved at: ${TIMESTAMP}
> Session: ${SESSION_HASH}

## Branch
${GIT_BRANCH:-N/A}

## Modified Files
${GIT_MODIFIED:-None}

## Staged Files
${GIT_STAGED:-None}

## Recent Commits
${GIT_LOG:-None}

## Project Instructions
${PROJECT_INSTRUCTIONS:-No CLAUDE.md found}

## User-Flagged Context
${REMEMBER_CONTENT:-No items saved. Use /allay:checkpoint <text> to save.}
"

# ── Enforce 50KB limit ──
CHECKPOINT_BYTES=${#CHECKPOINT}
if [[ "$CHECKPOINT_BYTES" -gt "$ALLAY_MAX_CHECKPOINT_BYTES" ]]; then
  CHECKPOINT="${CHECKPOINT:0:$ALLAY_MAX_CHECKPOINT_BYTES}

[truncated, checkpoint exceeded ${ALLAY_MAX_CHECKPOINT_BYTES} bytes]"
fi

# ── Write atomically with lock ──
acquire_lock "$LOCK_DIR" || exit 0

mkdir -p "$STATE_DIR"
printf "%s" "$CHECKPOINT" > "$CHECKPOINT_TMP"
mv "$CHECKPOINT_TMP" "$CHECKPOINT_FILE"

release_lock "$LOCK_DIR"

# ── Log metric ──
CHECKPOINT_SIZE=${#CHECKPOINT}
METRIC=$(jq -cn \
  --arg event "checkpoint_saved" \
  --arg ts "$TIMESTAMP" \
  --arg branch "${GIT_BRANCH:-unknown}" \
  --argjson size "$CHECKPOINT_SIZE" \
  '{event: $event, ts: $ts, size: $size, branch: $branch}')

log_metric "${STATE_DIR}/${ALLAY_METRICS_FILE##*/}" "$METRIC"

exit 0
