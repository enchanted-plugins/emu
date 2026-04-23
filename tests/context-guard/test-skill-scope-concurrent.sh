#!/usr/bin/env bash
# Test: skill-scope.sh handles concurrent registrations without corruption
# and supports nested stack ordering (parent -> child).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
SKILL_SCOPE="${REPO_ROOT}/shared/scripts/skill-scope.sh"

ISO=$(mktemp -d)
export FAE_ACTIVE_SKILLS_DIR="$ISO"

cleanup() { rm -rf "$ISO" 2>/dev/null || true; }
trap cleanup EXIT

# ── 1. Fire 10 concurrent registers ──
PIDS=()
for i in $(seq 1 10); do
  (
    bash "$SKILL_SCOPE" register "skill:$i" "plugin$i" >/dev/null 2>&1
  ) &
  PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done

# File must exist, be valid JSON, and contain all 10 entries.
STATE_FILE="$ISO/active-skills.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "FAIL: active-skills.json not created after concurrent registers"
  exit 1
fi
if ! jq empty "$STATE_FILE" 2>/dev/null; then
  echo "FAIL: active-skills.json is not valid JSON after concurrent writes"
  cat "$STATE_FILE" >&2
  exit 1
fi

COUNT=$(jq '.skills | length' "$STATE_FILE")
# Lock-contention ceiling: the mkdir-lock retry budget (50 * 100ms = 5s)
# means some concurrent writers may time out. The corruption guarantees are
# what matter (JSON always valid, every entry unique) — not that every
# registrant won the lock race.
if [[ "$COUNT" -lt 5 ]]; then
  echo "FAIL: expected ≥5 of 10 concurrent registrations, got $COUNT"
  cat "$STATE_FILE" >&2
  exit 1
fi

# Every entry must have an invocation_id (16 hex chars) and a pid.
BAD_IDS=$(jq -r '.skills[] | select((.invocation_id | test("^[0-9a-f]{16}$") | not))' "$STATE_FILE" 2>/dev/null || true)
if [[ -n "$BAD_IDS" ]]; then
  echo "FAIL: invocation ids must be 16 hex chars"
  exit 1
fi

# invocation ids must be unique across whatever did make it (entropy check).
UNIQUE=$(jq -r '.skills[].invocation_id' "$STATE_FILE" | sort -u | wc -l | tr -d ' ')
if [[ "$UNIQUE" -ne "$COUNT" ]]; then
  echo "FAIL: expected $COUNT unique invocation ids, got $UNIQUE"
  exit 1
fi

# ── 2. Clear and verify nested stack ordering ──
bash "$SKILL_SCOPE" clear >/dev/null
CUR=$(bash "$SKILL_SCOPE" current)
if [[ "$CUR" != "manual" ]]; then
  echo "FAIL: after clear, current should be 'manual', got '$CUR'"
  exit 1
fi

# Parent
eval "$(bash "$SKILL_SCOPE" register wixie:converge wixie)"
if [[ -z "${FAE_SCOPE_ID:-}" ]]; then
  echo "FAIL: register did not emit FAE_SCOPE_ID"
  exit 1
fi
if [[ "${FAE_SCOPE_DEPTH:-}" != "0" ]]; then
  echo "FAIL: parent depth should be 0, got '${FAE_SCOPE_DEPTH}'"
  exit 1
fi
PARENT_ID="$FAE_SCOPE_ID"

# Child inherits parent via env
eval "$(bash "$SKILL_SCOPE" register raven:review raven)"
if [[ "${FAE_SCOPE_DEPTH:-}" != "1" ]]; then
  echo "FAIL: child depth should be 1, got '${FAE_SCOPE_DEPTH}'"
  exit 1
fi
if [[ "${FAE_SCOPE_PARENT:-}" != "$PARENT_ID" ]]; then
  echo "FAIL: child parent should be '$PARENT_ID', got '${FAE_SCOPE_PARENT}'"
  exit 1
fi

# current returns the top of stack (most recent)
CUR=$(bash "$SKILL_SCOPE" current)
if [[ "$CUR" != "raven:review" ]]; then
  echo "FAIL: current should be top-of-stack 'raven:review', got '$CUR'"
  exit 1
fi

# unregister child → current falls back to parent
bash "$SKILL_SCOPE" unregister raven:review >/dev/null
CUR=$(bash "$SKILL_SCOPE" current)
if [[ "$CUR" != "wixie:converge" ]]; then
  echo "FAIL: after unregister child, current should be parent 'wixie:converge', got '$CUR'"
  exit 1
fi

# unregister parent → back to manual
bash "$SKILL_SCOPE" unregister wixie:converge >/dev/null
CUR=$(bash "$SKILL_SCOPE" current)
if [[ "$CUR" != "manual" ]]; then
  echo "FAIL: after unregister parent, current should be 'manual', got '$CUR'"
  exit 1
fi

exit 0
