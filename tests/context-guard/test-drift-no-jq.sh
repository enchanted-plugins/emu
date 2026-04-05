#!/usr/bin/env bash
# Test: detect-drift.sh exits 0 gracefully when jq is not available
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/context-guard/hooks/post-tool-use/detect-drift.sh"

# Run hook with PATH that excludes jq
EXIT_CODE=0
echo '{"tool_name":"Read"}' | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/context-guard" bash "$HOOK" >/dev/null 2>/dev/null || EXIT_CODE=$?

# Must exit 0 even without jq
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "FAIL: Hook should exit 0 without jq, got exit $EXIT_CODE"
  exit 1
fi

exit 0
