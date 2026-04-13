#!/usr/bin/env bash
# Test: sanitize_path blocks path traversal and accepts absolute paths
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

# shellcheck source=../../shared/sanitize.sh
source "${REPO_ROOT}/shared/sanitize.sh"

FAIL=0

# Helper
expect_pass() {
  local desc="$1"; shift
  if sanitize_path "$@" >/dev/null 2>&1; then
    true
  else
    echo "FAIL: should pass — $desc"
    FAIL=1
  fi
}

expect_fail() {
  local desc="$1"; shift
  if sanitize_path "$@" >/dev/null 2>&1; then
    echo "FAIL: should block — $desc"
    FAIL=1
  fi
}

# Block path traversal
expect_fail "literal .." "../etc/passwd"
expect_fail "URL-encoded .." "%2e%2e/etc/passwd"
expect_fail "mixed case URL-encoded" "%2E%2e/etc/passwd"
expect_fail "double-encoded" "%252e%252e/etc/passwd"
expect_fail "mid-path .." "/home/user/../etc/shadow"
expect_fail "empty path" ""

# Accept absolute paths (bug fix — was rejected before)
expect_pass "absolute path" "/home/user/project/file.ts"
expect_pass "absolute with project root" "/home/user/project/src/index.ts" "/home/user/project"

# Block paths outside project root
expect_fail "outside project root" "/etc/shadow" "/home/user/project"

# Accept relative paths under project root
expect_pass "relative under root" "src/index.ts" "/home/user/project"

if [[ $FAIL -ne 0 ]]; then
  exit 1
fi

exit 0
