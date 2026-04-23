#!/usr/bin/env bash
# Emu A8 — Skill-Scoped Attribution
#
# Shared registration API for any enchanted-plugins skill. When a skill opens
# (e.g. /wixie:converge begins its 100-iteration loop), it calls:
#
#     shared/scripts/skill-scope.sh register <skill_id> <plugin_name>
#
# On close, it calls:
#
#     shared/scripts/skill-scope.sh unregister <skill_id>
#
# The context-guard PostToolUse hook reads the currently-active scope and tags
# every metrics event with it, so /fae:analytics can show who spent what.
#
# Design notes (why these choices):
#   - Stored as an array to support nested/concurrent skills — worktrees can run
#     skills in parallel, and one skill can invoke another. Matches structlog's
#     nested-bind model and OTel span parent/child.
#   - Each scope gets a 16-hex-char invocation_id (systemd InvocationID pattern) —
#     PIDs reuse, invocation IDs don't.
#   - Stale eviction on every read: we drop entries whose PID is dead OR whose
#     started_at + FAE_SKILL_TTL is past. Both guards — `kill -0` fails
#     silently on MSYS/Cygwin for some PIDs, so the TTL is the safety net.
#   - Atomic write: write to .tmp, validate JSON, rename. No flock — atomic
#     mkdir lock per the brand standard.
#   - State file lives in context-guard's state/ so all plugins have a single
#     source of truth without cross-plugin coupling.
#
# State file schema (${CONTEXT_GUARD_STATE}/active-skills.json):
#   {
#     "version": 1,
#     "skills": [
#       {
#         "skill_id": "wixie:converge",
#         "plugin": "wixie",
#         "invocation_id": "a1b2c3d4e5f67890",
#         "parent_invocation_id": "" | "<id>",
#         "depth": 0,
#         "started_at": "2026-04-16T12:34:56Z",
#         "pid": 12345,
#         "worktree": "apps/sigil",
#         "session_id": "abc123def456"
#       }
#     ]
#   }

set +e
trap 'exit 0' ERR INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SHARED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../constants.sh
source "${SHARED_DIR}/constants.sh"
# shellcheck source=../metrics.sh
source "${SHARED_DIR}/metrics.sh"

# ── jq required ──
if ! command -v jq >/dev/null 2>&1; then
  # Graceful degradation — "current" prints "manual", register/unregister no-op.
  case "${1:-}" in
    current) printf "manual\n" ;;
    list)    printf '{"version":1,"skills":[]}\n' ;;
    *)       ;;
  esac
  exit 0
fi

# ── Resolve state directory ──
# Priority:
#   1. FAE_ACTIVE_SKILLS_DIR env var (tests use this)
#   2. CLAUDE_PLUGIN_ROOT env var + state/ (when called from a hook)
#   3. <repo>/plugins/context-guard/state/ (sibling lookup from shared/)
if [[ -n "${FAE_ACTIVE_SKILLS_DIR:-}" ]]; then
  STATE_DIR="$FAE_ACTIVE_SKILLS_DIR"
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -d "${CLAUDE_PLUGIN_ROOT}" ]]; then
  STATE_DIR="${CLAUDE_PLUGIN_ROOT}/state"
  # If we were called from a non-context-guard plugin, redirect to context-guard.
  case "$CLAUDE_PLUGIN_ROOT" in
    */context-guard) ;;
    */plugins/*)
      _sc_plugins_root="${CLAUDE_PLUGIN_ROOT%/*}"
      if [[ -d "${_sc_plugins_root}/context-guard" ]]; then
        STATE_DIR="${_sc_plugins_root}/context-guard/state"
      fi
      unset _sc_plugins_root
      ;;
  esac
else
  # shared/scripts -> shared -> repo root
  _sc_repo_root="$(cd "${SHARED_DIR}/.." && pwd)"
  STATE_DIR="${_sc_repo_root}/plugins/context-guard/state"
  unset _sc_repo_root
fi

STATE_FILE="${STATE_DIR}/active-skills.json"
LOCK_DIR="${STATE_FILE}${FAE_LOCK_SUFFIX}"

# Ensure parent dir exists — acquire_lock uses `mkdir <dir>` (no -p), so the
# parent must exist first, otherwise every call here returns before writing.
mkdir -p "$STATE_DIR" 2>/dev/null || true

# ── Helpers ──

# 16-hex-char invocation id.
_sc_gen_invocation_id() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 8 2>/dev/null && return 0
  fi
  # Portable fallback: two RANDOMs + pid + epoch, hashed.
  local seed="${RANDOM}${RANDOM}${RANDOM}$$$(date +%s%N 2>/dev/null || date +%s)"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$seed" | sha256sum | cut -c1-16
  elif command -v md5sum >/dev/null 2>&1; then
    printf "%s" "$seed" | md5sum | cut -c1-16
  else
    printf "%016x" $(( (RANDOM * 32768 + RANDOM) * 32768 + RANDOM ))
  fi
}

# Read the file (or a fresh skeleton) with stale entries purged.
# Writes the cleaned JSON to stdout. Always valid JSON.
_sc_read_clean() {
  local raw='{"version":1,"skills":[]}'
  if [[ -f "$STATE_FILE" ]]; then
    local file_contents
    file_contents=$(cat "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$file_contents" ]] && printf "%s" "$file_contents" | jq empty >/dev/null 2>&1; then
      raw="$file_contents"
    fi
  fi

  local now ttl
  now=$(date -u +%s)
  ttl="${FAE_SKILL_TTL:-3600}"

  # Build a space-separated list of live PIDs to filter against.
  # We check each PID once (kill -0). Dead PIDs yield empty.
  local pids live_pids=""
  pids=$(printf "%s" "$raw" | jq -r '.skills[]?.pid // empty' 2>/dev/null | sort -u)
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      live_pids+=" ${pid}"
    fi
  done <<<"$pids"
  # Normalize: " 123 456 " -> "123 456"
  live_pids="${live_pids# }"

  printf "%s" "$raw" | jq --arg live "$live_pids" --argjson now "$now" --argjson ttl "$ttl" '
    ($live | split(" ") | map(select(length>0))) as $alive |
    {
      version: 1,
      skills: (
        [ .skills[]?
          | . as $s
          | ( ($s.started_at_epoch // null) ) as $epoch
          | ($s.pid | tostring) as $pid_str
          | select(
              ($alive | index($pid_str)) != null
              and (($epoch == null) or (($now - $epoch) < $ttl))
            )
        ]
      )
    }
  '
}

# Atomic write: write to .tmp, validate, rename. Caller holds the lock.
_sc_write_atomic() {
  local payload="$1"
  if ! printf "%s" "$payload" | jq empty >/dev/null 2>&1; then
    return 1
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  local tmp="${STATE_FILE}.$$.tmp"
  printf "%s\n" "$payload" > "$tmp" 2>/dev/null || return 1
  mv "$tmp" "$STATE_FILE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# ── Commands ──

cmd_register() {
  local skill_id="${1:-}"
  local plugin="${2:-}"
  if [[ -z "$skill_id" ]] || [[ -z "$plugin" ]]; then
    printf "usage: skill-scope.sh register <skill_id> <plugin>\n" >&2
    return 2
  fi

  # Owner PID: skill's parent (Claude), not this bash subshell.
  local owner_pid="${FAE_SKILL_OWNER_PID:-$PPID}"
  local invocation_id parent_id depth started_at started_epoch
  invocation_id=$(_sc_gen_invocation_id)
  parent_id="${FAE_SCOPE_ID:-}"
  depth="${FAE_SCOPE_DEPTH:-0}"
  if [[ -n "$parent_id" ]]; then depth=$((depth + 1)); fi
  started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  started_epoch=$(date -u +%s)

  # Worktree + session context (best effort; may be empty if session-init not loaded).
  local worktree session_id
  worktree="${FAE_WORKTREE_REL:-}"
  session_id="${FAE_SESSION_ID:-}"

  acquire_lock "$LOCK_DIR" || return 1

  local cleaned updated
  cleaned=$(_sc_read_clean)
  updated=$(printf "%s" "$cleaned" | jq -c \
    --arg sid "$skill_id" \
    --arg plugin "$plugin" \
    --arg iid "$invocation_id" \
    --arg pid_id "$parent_id" \
    --argjson depth "$depth" \
    --arg started "$started_at" \
    --argjson started_epoch "$started_epoch" \
    --argjson pid "$owner_pid" \
    --arg wt "$worktree" \
    --arg ses "$session_id" \
    '.skills += [{
       skill_id:$sid, plugin:$plugin,
       invocation_id:$iid, parent_invocation_id:$pid_id, depth:$depth,
       started_at:$started, started_at_epoch:$started_epoch,
       pid:$pid, worktree:$wt, session_id:$ses
     }]')

  if [[ -n "$updated" ]]; then
    _sc_write_atomic "$updated" || true
  fi
  release_lock "$LOCK_DIR"

  # Emit `export` statements so callers can adopt the scope via:
  #   eval "$(skill-scope.sh register ...)"
  # Values are bounded character sets (hex/int/skill_id), so no shell-quoting
  # is required.
  printf "export FAE_SCOPE_ID=%s\nexport FAE_SCOPE_PARENT=%s\nexport FAE_SCOPE_DEPTH=%s\nexport FAE_SCOPE_SKILL=%s\n" \
    "$invocation_id" "$parent_id" "$depth" "$skill_id"
}

cmd_unregister() {
  local skill_id="${1:-}"
  # Optional explicit invocation_id (2nd arg only — we don't auto-use
  # FAE_SCOPE_ID because in nested flows it may refer to a child scope).
  local invocation_id="${2:-}"
  if [[ -z "$skill_id" ]]; then
    printf "usage: skill-scope.sh unregister <skill_id> [invocation_id]\n" >&2
    return 2
  fi

  acquire_lock "$LOCK_DIR" || return 1

  local cleaned updated
  cleaned=$(_sc_read_clean)
  if [[ -n "$invocation_id" ]]; then
    updated=$(printf "%s" "$cleaned" | jq -c --arg sid "$skill_id" --arg iid "$invocation_id" \
      '.skills |= map(select(.skill_id != $sid or .invocation_id != $iid))')
  else
    # Remove the most recent entry for this skill_id (LIFO).
    updated=$(printf "%s" "$cleaned" | jq -c --arg sid "$skill_id" '
      (.skills | map(.skill_id == $sid) | (length - 1) - (reverse | index(true) // -1)) as $idx |
      if $idx < 0 then .
      else .skills |= (.[0:$idx] + .[$idx+1:])
      end
    ')
  fi

  if [[ -n "$updated" ]]; then
    _sc_write_atomic "$updated" || true
  fi
  release_lock "$LOCK_DIR"
}

cmd_current() {
  # Locking for read is not strictly required, but it makes concurrent
  # register+current deterministic.
  acquire_lock "$LOCK_DIR" || { printf "manual\n"; return 0; }
  local cleaned
  cleaned=$(_sc_read_clean)
  # Persist the cleaned view so stale entries don't accumulate.
  _sc_write_atomic "$cleaned" || true
  release_lock "$LOCK_DIR"

  # tr -d '\r' defends against jq's CRLF output on Windows stdout.
  local top
  top=$(printf "%s" "$cleaned" | jq -r '.skills[-1].skill_id // "manual"' 2>/dev/null | tr -d '\r')
  printf "%s\n" "${top:-manual}"
}

# Emit full details of the top-of-stack as shell exports (one KEY=VALUE per line).
# Values never contain shell metas (skill_id/plugin/hex ids/int), so consumers
# can parse with `while IFS='=' read -r k v`.
# tr -d '\r' defends against jq's CRLF output on Windows stdout.
cmd_current_env() {
  acquire_lock "$LOCK_DIR" || { printf "FAE_SCOPE_SKILL=manual\nFAE_SCOPE_PLUGIN=\nFAE_SCOPE_ID=\nFAE_SCOPE_PARENT=\nFAE_SCOPE_DEPTH=0\n"; return 0; }
  local cleaned
  cleaned=$(_sc_read_clean)
  _sc_write_atomic "$cleaned" || true
  release_lock "$LOCK_DIR"

  printf "%s" "$cleaned" | jq -r '
    (.skills[-1] // {skill_id:"manual", plugin:"", invocation_id:"", parent_invocation_id:"", depth:0}) as $t |
    "FAE_SCOPE_SKILL=\($t.skill_id // "manual")",
    "FAE_SCOPE_PLUGIN=\($t.plugin // "")",
    "FAE_SCOPE_ID=\($t.invocation_id // "")",
    "FAE_SCOPE_PARENT=\($t.parent_invocation_id // "")",
    "FAE_SCOPE_DEPTH=\($t.depth // 0)"
  ' 2>/dev/null | tr -d '\r'
}

cmd_list() {
  acquire_lock "$LOCK_DIR" || { printf '{"version":1,"skills":[]}\n'; return 0; }
  local cleaned
  cleaned=$(_sc_read_clean)
  _sc_write_atomic "$cleaned" || true
  release_lock "$LOCK_DIR"
  printf "%s\n" "$cleaned"
}

cmd_clear() {
  acquire_lock "$LOCK_DIR" || return 0
  _sc_write_atomic '{"version":1,"skills":[]}' || true
  release_lock "$LOCK_DIR"
}

# ── Dispatch ──
case "${1:-current}" in
  register)     shift; cmd_register "$@" ;;
  unregister)   shift; cmd_unregister "$@" ;;
  current)      cmd_current ;;
  current-env)  cmd_current_env ;;
  list)         cmd_list ;;
  clear)        cmd_clear ;;
  *)
    printf "usage: skill-scope.sh {register|unregister|current|current-env|list|clear}\n" >&2
    exit 2
    ;;
esac
