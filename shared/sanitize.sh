#!/usr/bin/env bash
# Allay shared sanitization utilities

sanitize_path() {
  local path="$1"
  [[ -z "$path" ]] && return 1

  # Decode URL-encoded path traversal (spec rule #9)
  local decoded
  decoded=$(printf "%s" "$path" \
    | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')

  # Block path traversal
  if [[ "$decoded" == *".."* ]]; then return 1; fi

  # Block absolute and home-relative paths
  if [[ "$decoded" == /* ]] || [[ "$decoded" == ~* ]]; then return 1; fi

  # Block null bytes
  if printf "%s" "$decoded" | grep -qP '\x00' 2>/dev/null; then return 1; fi

  echo "$decoded"
  return 0
}

validate_json() {
  printf "%s" "$1" | jq empty >/dev/null 2>&1
}

sanitize_for_log() {
  printf "%s" "$1" \
    | sed -E \
      -e 's/(sk-ant-[a-zA-Z0-9]+)/[REDACTED]/g' \
      -e 's/(shpss_[a-zA-Z0-9]+)/[REDACTED]/g' \
      -e 's/(password|secret|token)=[^ ]*/\1=[REDACTED]/gi'
}
