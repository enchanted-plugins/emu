#!/usr/bin/env bash
# Test: compress-bash.sh applies ALL compression rules correctly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/token-saver/hooks/pre-tool-use/compress-bash.sh"
STATE_DIR="${REPO_ROOT}/plugins/token-saver/state"

rm -f "${STATE_DIR}/metrics.jsonl"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

test_rule() {
  local cmd="$1"
  local expected="$2"
  local rule_name="$3"

  local INPUT
  INPUT=$(jq -n \
    --arg transcript "$MOCK_TRANSCRIPT" \
    --arg cmd "$cmd" \
    '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Bash", tool_input: {command: $cmd}, hook_event_name: "PreToolUse"}')

  local OUTPUT
  OUTPUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/token-saver" bash "$HOOK" 2>/dev/null || true)

  if [[ -z "$OUTPUT" ]]; then
    echo "FAIL: $rule_name — no output for: $cmd"
    rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
    rm -rf "${STATE_DIR}/metrics.jsonl.lock"
    exit 1
  fi

  local MODIFIED_CMD
  MODIFIED_CMD=$(printf "%s" "$OUTPUT" | jq -r '.hookSpecificOutput.updatedInput.command' 2>/dev/null)

  if [[ "$MODIFIED_CMD" != *"$expected"* ]]; then
    echo "FAIL: $rule_name — expected '$expected' in output, got: $MODIFIED_CMD"
    rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
    rm -rf "${STATE_DIR}/metrics.jsonl.lock"
    exit 1
  fi
}

# Test all compression rules — check for key fragments in the modified command
test_rule "npm test" "tail -n 40" "test_tail (npm)"
test_rule "yarn test" "tail -n 40" "test_tail (yarn)"
test_rule "vitest" "tail -n 40" "test_tail (vitest)"
test_rule "jest" "tail -n 40" "test_tail (jest)"
test_rule "pytest" "tail -n 30" "pytest_filter"
test_rule "python -m pytest" "tail -n 30" "pytest_filter (module)"
test_rule "go test" "tail -n 30" "gotest_filter"
test_rule "mvn test" "tail -n 20" "jvm_test_filter (mvn)"
test_rule "gradle test" "tail -n 20" "jvm_test_filter (gradle)"
test_rule "dotnet build" "tail -n 20" "dotnet_filter (build)"
test_rule "dotnet test" "tail -n 20" "dotnet_filter (test)"
test_rule "npm install" "tail -n 20" "install_filter"
test_rule "cargo build" "tail -n 30" "cargo_filter"
test_rule "cargo test" "tail -n 30" "cargo_filter"
test_rule "docker build ." "tail -n 30" "docker_build_filter"
test_rule "terraform plan" "tail -n 10" "terraform_plan_filter"
test_rule "eslint src/" "head -n 20" "eslint_filter"
test_rule "tsc" "head -n 20" "tsc_filter"
test_rule "git log" "--oneline -20" "git_log_trim"
test_rule "find . -name '*.js'" "head -n 30" "find_head"

# Cleanup
rm -f "$MOCK_TRANSCRIPT" "${STATE_DIR}/metrics.jsonl"
rm -rf "${STATE_DIR}/metrics.jsonl.lock"

exit 0
