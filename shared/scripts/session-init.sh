#!/usr/bin/env bash
# Emu session initializer — A9 Worktree Session Graph
#
# Sourced by hooks to resolve, once per process:
#   FAE_REPO_ID           stable identity across clones/worktrees (root-commit-hash[:12])
#   FAE_WORKTREE_PATH     absolute path to this worktree's toplevel
#   FAE_MAIN_WORKTREE     absolute path to the main (first) worktree
#   FAE_WORKTREE_REL      worktree label relative to main ("." for main, else short label)
#   FAE_IS_WORKTREE       "1" if running inside a linked worktree, "0" on main
#   FAE_SESSION_ID        12-hex-char session id, persisted in plugin state/.session
#   FAE_HOST              short hostname
#   FAE_GLOBAL_STATE_DIR  $XDG_STATE_HOME/fae/<repo_id>/  (metrics shards live here)
#   FAE_GLOBAL_DATA_DIR   $XDG_DATA_HOME/fae/<repo_id>/   (learnings.json lives here)
#
# Contract:
#   - Never prints to stdout/stderr. Exports vars.
#   - Always returns 0 — missing git / missing commands degrade to best-effort fallbacks.
#   - Safe to source multiple times (early-return if FAE_REPO_ID already set).

if [[ -n "${FAE_REPO_ID:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Source constants if not already loaded
if [[ -z "${FAE_LOCK_SUFFIX:-}" ]]; then
  _si_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=../constants.sh
  source "${_si_SCRIPT_DIR}/../constants.sh"
fi

# ── Repo identity (root-commit hash, stable across clones and worktrees) ──
_si_compute_repo_id() {
  local cwd="${1:-$PWD}"
  local root_commit=""
  if command -v git >/dev/null 2>&1; then
    root_commit=$(cd "$cwd" && git rev-list --max-parents=0 HEAD 2>/dev/null | head -n 1 || true)
  fi
  if [[ -z "$root_commit" ]]; then
    # Fallback: hash of absolute toplevel path (worktree-specific but deterministic)
    local fallback
    if command -v git >/dev/null 2>&1; then
      fallback=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null || pwd)
    else
      fallback="$cwd"
    fi
    printf "%s" "$fallback" | _si_hash12
    return 0
  fi
  printf "%s" "$root_commit" | _si_hash12
}

# 12-hex-char hash of stdin. Prefers sha256sum, falls back to md5sum, then a trivial reducer.
_si_hash12() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -c1-12
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-12
  elif command -v md5sum >/dev/null 2>&1; then
    md5sum | cut -c1-12
  else
    # Last-resort deterministic reducer (not cryptographic, but present everywhere).
    cksum | awk '{printf "%012x", $1}' | cut -c1-12
  fi
}

# ── Worktree resolution ──
_si_resolve_worktree() {
  local cwd="${1:-$PWD}"
  FAE_WORKTREE_PATH=""
  FAE_MAIN_WORKTREE=""
  FAE_IS_WORKTREE="0"
  FAE_WORKTREE_REL="."

  if ! command -v git >/dev/null 2>&1; then
    FAE_WORKTREE_PATH="$cwd"
    FAE_MAIN_WORKTREE="$cwd"
    return 0
  fi

  FAE_WORKTREE_PATH=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null || echo "$cwd")

  # First entry of `git worktree list --porcelain` is always the main worktree.
  local first_wt
  first_wt=$(cd "$cwd" && git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
  FAE_MAIN_WORKTREE="${first_wt:-$FAE_WORKTREE_PATH}"

  if [[ "$FAE_WORKTREE_PATH" != "$FAE_MAIN_WORKTREE" ]]; then
    FAE_IS_WORKTREE="1"
    # Prefer a path relative to main; fall back to basename if not a descendant.
    local rel=""
    case "$FAE_WORKTREE_PATH" in
      "$FAE_MAIN_WORKTREE"/*)
        rel="${FAE_WORKTREE_PATH#"$FAE_MAIN_WORKTREE"/}"
        ;;
      *)
        rel=$(basename "$FAE_WORKTREE_PATH")
        ;;
    esac
    FAE_WORKTREE_REL="$rel"
  fi
}

# ── Session id: 12 hex chars, persisted per (plugin, worktree) ──
_si_resolve_session_id() {
  local marker_dir="${1:-}"
  local marker_file="${marker_dir}/.session"
  local session_id=""

  if [[ -n "$marker_dir" ]] && [[ -f "$marker_file" ]]; then
    session_id=$(head -n 1 "$marker_file" 2>/dev/null | tr -dc 'a-f0-9' | cut -c1-12 || true)
  fi

  if [[ -z "$session_id" ]] || [[ ${#session_id} -lt 12 ]]; then
    local start_ts
    start_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    session_id=$(printf "%s|%s|%s|%s" "$FAE_REPO_ID" "$FAE_WORKTREE_PATH" "$start_ts" "$$" | _si_hash12)

    if [[ -n "$marker_dir" ]]; then
      mkdir -p "$marker_dir" 2>/dev/null || true
      if [[ -w "$marker_dir" ]] || mkdir -p "$marker_dir" 2>/dev/null; then
        local tmp="${marker_file}.$$.tmp"
        printf "%s\n" "$session_id" > "$tmp" 2>/dev/null && mv "$tmp" "$marker_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
      fi
    fi
  fi
  FAE_SESSION_ID="$session_id"
}

# ── Main ──
_si_cwd="${FAE_INIT_CWD:-$PWD}"
_si_plugin_state="${FAE_PLUGIN_STATE_DIR:-}"

FAE_REPO_ID="$(_si_compute_repo_id "$_si_cwd")"
_si_resolve_worktree "$_si_cwd"
_si_resolve_session_id "$_si_plugin_state"

FAE_HOST=$(hostname 2>/dev/null | awk -F. '{print $1}' || echo "unknown")

FAE_GLOBAL_STATE_DIR="${FAE_XDG_STATE_HOME}/${FAE_GLOBAL_STATE_SUBDIR}/${FAE_REPO_ID}"
FAE_GLOBAL_DATA_DIR="${FAE_XDG_DATA_HOME}/${FAE_GLOBAL_DATA_SUBDIR}/${FAE_REPO_ID}"

mkdir -p "$FAE_GLOBAL_STATE_DIR" 2>/dev/null || true
mkdir -p "$FAE_GLOBAL_DATA_DIR" 2>/dev/null || true

export FAE_REPO_ID FAE_WORKTREE_PATH FAE_MAIN_WORKTREE FAE_WORKTREE_REL FAE_IS_WORKTREE
export FAE_SESSION_ID FAE_HOST FAE_GLOBAL_STATE_DIR FAE_GLOBAL_DATA_DIR

unset _si_cwd _si_plugin_state _si_SCRIPT_DIR
unset -f _si_compute_repo_id _si_hash12 _si_resolve_worktree _si_resolve_session_id 2>/dev/null || true

return 0 2>/dev/null || exit 0
