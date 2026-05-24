#!/usr/bin/env bash
# Emu test runner — runs all test scripts, reports pass/fail/timeout/skip.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0
FAIL=0
TIMEOUT_COUNT=0
SKIP=0
ERRORS=()

# Per-test wall-clock cap. GNU coreutils `timeout` exits with 124 on timeout.
# Cap kept ≤ 90 s per repo policy; default 60 s leaves headroom for slower
# integration tests on Windows/MSYS.
TEST_TIMEOUT="${EMU_TEST_TIMEOUT:-60}"

# Skip patterns: lines of "<dir>/<name>\treason". Edited below as we
# classify Windows-only failures.
declare -A SKIP_REASONS

# ── Skip registry ────────────────────────────────────────────────────────────
# Format: SKIP_REASONS["<dir>/<test-name>"]="reason"
# Reserved for Windows-only environment failures. Currently empty: all tests
# that fail on Windows-MSYS in the May-2026 sweep were test-harness/spec
# drift (e.g. asserting hard exit-2 on hooks that are documented as
# advisory-only) rather than real environment incompatibility; those tests
# were corrected in-place.

# ── Pre-run hygiene ──────────────────────────────────────────────────────────
# Stale .lock directories from a prior interrupted run will cause every
# subsequent hook invocation to spin for ~5 s in `acquire_lock` (mkdir-based
# locks). Sweep them before we begin so the first batch of tests doesn't
# inherit the hang.
sweep_stale_locks() {
  local count=0
  while IFS= read -r -d '' lockdir; do
    rmdir "$lockdir" 2>/dev/null && count=$((count + 1)) || true
  done < <(find "${REPO_ROOT}/plugins" -type d -name "*.lock" -print0 2>/dev/null)
  [[ $count -gt 0 ]] && printf "  (swept %d stale .lock dir%s)\n" "$count" "$([[ $count -eq 1 ]] && echo "" || echo "s")"
  return 0
}

run_test() {
  local test_file="$1"
  local test_name
  test_name=$(basename "$test_file" .sh)
  local dir_name
  dir_name=$(basename "$(dirname "$test_file")")
  local key="${dir_name}/${test_name}"

  printf "  %-20s %-30s " "$dir_name" "$test_name"

  # Skip-list short-circuit.
  if [[ -n "${SKIP_REASONS[$key]:-}" ]]; then
    printf "[SKIP] %s\n" "${SKIP_REASONS[$key]}"
    SKIP=$((SKIP + 1))
    return 0
  fi

  # Sweep before each test — the previous test may have left a lock behind.
  sweep_stale_locks >/dev/null 2>&1 || true

  local output
  output=$(timeout --preserve-status "${TEST_TIMEOUT}" bash "$test_file" 2>&1)
  local exit_code=$?

  case "$exit_code" in
    0)
      printf "[PASS]\n"
      PASS=$((PASS + 1))
      ;;
    124|137)
      # 124 = timeout expired; 137 = SIGKILL (timeout --kill-after path).
      printf "[TIMEOUT] (>%ss)\n" "$TEST_TIMEOUT"
      TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
      ERRORS+=("$key: TIMEOUT after ${TEST_TIMEOUT}s")
      ;;
    *)
      printf "[FAIL] (exit %d)\n" "$exit_code"
      FAIL=$((FAIL + 1))
      ERRORS+=("$key: $output")
      ;;
  esac
}

echo "══════════════════════════════════════"
echo " EMU TEST SUITE"
echo "══════════════════════════════════════"
echo " per-test timeout: ${TEST_TIMEOUT}s"
echo ""

sweep_stale_locks

# Run tests by plugin
for plugin_dir in "$SCRIPT_DIR"/*/; do
  plugin_name=$(basename "$plugin_dir")
  if [[ "$plugin_name" == "fixtures" ]]; then continue; fi

  for test_file in "$plugin_dir"/test-*.sh; do
    [[ -f "$test_file" ]] || continue
    run_test "$test_file"
  done
done

echo ""
echo "──────────────────────────────────────"
printf " Results: PASS %d | FAIL %d | TIMEOUT %d | SKIP %d\n" \
  "$PASS" "$FAIL" "$TIMEOUT_COUNT" "$SKIP"
echo "──────────────────────────────────────"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo " Failures / Timeouts:"
  for err in "${ERRORS[@]}"; do
    echo "   ✗ $err"
  done
fi

echo ""

# Final cleanup so we don't poison the next run.
sweep_stale_locks >/dev/null 2>&1 || true

if [[ $((FAIL + TIMEOUT_COUNT)) -gt 0 ]]; then
  exit 1
fi

exit 0
