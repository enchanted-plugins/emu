#!/usr/bin/env bash
# Test: entries with a dead owner PID are evicted on next read, without
# requiring explicit unregister. Verifies A8's stale-cleanup path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
SKILL_SCOPE="${REPO_ROOT}/shared/scripts/skill-scope.sh"

ISO=$(mktemp -d)
export FAE_ACTIVE_SKILLS_DIR="$ISO"

cleanup() { rm -rf "$ISO" 2>/dev/null || true; }
trap cleanup EXIT

# ── Get a guaranteed-dead PID: spawn a subshell, capture its pid, wait for exit ──
DEAD_PID=$(bash -c 'echo $$' 2>/dev/null)
# Sanity: that subshell should now be gone.
if kill -0 "$DEAD_PID" 2>/dev/null; then
  # Very rare: the OS reassigned the same PID to something long-lived before
  # we got here. Bail — we can't test eviction against a live PID.
  echo "SKIP: PID $DEAD_PID appears live (OS reused it); cannot test stale eviction"
  exit 0
fi

# ── Hand-craft an entry with that dead PID (bypass register to force the condition) ──
NOW=$(date -u +%s)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$ISO/active-skills.json" <<JSON
{
  "version": 1,
  "skills": [
    {
      "skill_id": "zombie:skill",
      "plugin": "zombie",
      "invocation_id": "aaaaaaaaaaaaaaaa",
      "parent_invocation_id": "",
      "depth": 0,
      "started_at": "$TS",
      "started_at_epoch": $NOW,
      "pid": $DEAD_PID,
      "worktree": ".",
      "session_id": "ghostsession"
    }
  ]
}
JSON

# Pre-check: the file DOES contain the zombie entry right now.
PRE=$(jq '.skills | length' "$ISO/active-skills.json")
if [[ "$PRE" -ne 1 ]]; then
  echo "FAIL: setup sanity — expected 1 entry pre-read, got $PRE"
  exit 1
fi

# ── Trigger a read (which runs _sc_read_clean + persists the cleaned state) ──
CUR=$(bash "$SKILL_SCOPE" current)
if [[ "$CUR" != "manual" ]]; then
  echo "FAIL: stale entry should have been evicted — expected 'manual', got '$CUR'"
  exit 1
fi

# ── Verify the file was rewritten without the zombie ──
POST=$(jq '.skills | length' "$ISO/active-skills.json")
if [[ "$POST" -ne 0 ]]; then
  echo "FAIL: expected 0 entries after eviction, got $POST"
  cat "$ISO/active-skills.json" >&2
  exit 1
fi

# ── Additionally verify TTL-based eviction: write an entry with LIVE pid but ancient started_at ──
# Use this shell's PID (guaranteed alive).
OWN_PID=$$
ANCIENT_EPOCH=$((NOW - 99999))  # well past 1h TTL
cat > "$ISO/active-skills.json" <<JSON
{
  "version": 1,
  "skills": [
    {
      "skill_id": "elder:skill",
      "plugin": "elder",
      "invocation_id": "bbbbbbbbbbbbbbbb",
      "parent_invocation_id": "",
      "depth": 0,
      "started_at": "2000-01-01T00:00:00Z",
      "started_at_epoch": $ANCIENT_EPOCH,
      "pid": $OWN_PID,
      "worktree": ".",
      "session_id": "ancientsession"
    }
  ]
}
JSON

CUR=$(FAE_SKILL_TTL=3600 bash "$SKILL_SCOPE" current)
if [[ "$CUR" != "manual" ]]; then
  echo "FAIL: TTL-aged entry (live pid but >TTL old) should be evicted, got '$CUR'"
  exit 1
fi

POST_TTL=$(jq '.skills | length' "$ISO/active-skills.json")
if [[ "$POST_TTL" -ne 0 ]]; then
  echo "FAIL: expected 0 entries after TTL eviction, got $POST_TTL"
  exit 1
fi

exit 0
