#!/usr/bin/env bash
# Emu session report generator
# Generates a text-based session health report.
# If Python 3 is available, generates a dark-themed PDF report.
# Not time-critical — called on demand via /fae:report.
#
# Usage: bash report-gen.sh <plugins_dir> [output_path]
#   plugins_dir: path to the plugins/ directory
#   output_path: optional path for PDF output (default: /tmp/fae-report-<ts>.txt)

trap 'exit 0' ERR INT TERM

set -uo pipefail

PLUGINS_DIR="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ -z "$PLUGINS_DIR" ]]; then
  echo "Usage: report-gen.sh <plugins_dir> [output_path]" >&2
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TS_SHORT=$(date -u +"%Y%m%d-%H%M%S")

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="/tmp/fae-report-${TS_SHORT}.txt"
fi

# ── Gather metrics from all plugins ──
SK_METRICS="${PLUGINS_DIR}/state-keeper/state/metrics.jsonl"
TS_METRICS="${PLUGINS_DIR}/token-saver/state/metrics.jsonl"
CG_METRICS="${PLUGINS_DIR}/context-guard/state/metrics.jsonl"

# Count events (safe grep with fallback)
count_events() {
  local file="$1"
  local event="$2"
  local count=0
  if [[ -f "$file" ]]; then
    count=$(grep -c "\"${event}\"" "$file" 2>/dev/null) || true
    count=$(echo "$count" | tr -d '[:space:]')
  fi
  echo "${count:-0}"
}

CHECKPOINTS=$(count_events "$SK_METRICS" "checkpoint_saved")
COMPRESSIONS=$(count_events "$TS_METRICS" "bash_compressed")
DUPLICATES=$(count_events "$TS_METRICS" "duplicate_blocked")
DELTAS=$(count_events "$TS_METRICS" "delta_read")
DRIFT_ALERTS=$(count_events "$CG_METRICS" "drift_detected")
AGED_RESULTS=$(count_events "$TS_METRICS" "result_aged")
TURNS=$(count_events "$CG_METRICS" "turn")

# Calculate savings (conservative multipliers)
COMPRESSION_SAVINGS=$((COMPRESSIONS * 2))
DUPLICATE_SAVINGS=$((DUPLICATES * 4))
DRIFT_SAVINGS=$((DRIFT_ALERTS * 800 / 1000))  # 800 tokens each, in K
TOTAL_SAVINGS=$((COMPRESSION_SAVINGS + DUPLICATE_SAVINGS + DRIFT_SAVINGS))

# Runway calculation from last 5 turn events
AVG_TOKENS=0
RUNWAY="N/A"
if [[ -f "$CG_METRICS" ]] && [[ "$TURNS" -gt 0 ]]; then
  RECENT_TOKENS=$(grep '"event":"turn"' "$CG_METRICS" 2>/dev/null | tail -5 | jq -r '.tokens_est // 0' 2>/dev/null | awk '{s+=$1} END{print s+0}' 2>/dev/null || echo "0")
  RECENT_COUNT=$(grep '"event":"turn"' "$CG_METRICS" 2>/dev/null | tail -5 | wc -l | tr -d '[:space:]')
  if [[ "$RECENT_COUNT" -gt 0 ]] && [[ "$RECENT_TOKENS" -gt 0 ]]; then
    AVG_TOKENS=$((RECENT_TOKENS / RECENT_COUNT))
    if [[ "$AVG_TOKENS" -gt 0 ]]; then
      TOTAL_USED=$((AVG_TOKENS * TURNS))
      REMAINING=$((200000 - TOTAL_USED))
      if [[ "$REMAINING" -gt 0 ]]; then
        RUNWAY=$((REMAINING / AVG_TOKENS))
      else
        RUNWAY="0"
      fi
    fi
  fi
fi

# Drift breakdown
DRIFT_READ=$(count_events "$CG_METRICS" "read_loop")
DRIFT_EDIT=$(count_events "$CG_METRICS" "edit_revert")
DRIFT_FAIL=$(count_events "$CG_METRICS" "test_fail_loop")

# Session duration estimate
FIRST_TS=""
LAST_TS=""
if [[ -f "$CG_METRICS" ]]; then
  FIRST_TS=$(head -1 "$CG_METRICS" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null)
  LAST_TS=$(tail -1 "$CG_METRICS" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null)
fi

DURATION_MIN="?"
if [[ -n "$FIRST_TS" ]] && [[ -n "$LAST_TS" ]]; then
  # Try to compute duration (best-effort)
  FIRST_EPOCH=$(date -d "$FIRST_TS" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$FIRST_TS" +%s 2>/dev/null || echo "0")
  LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_TS" +%s 2>/dev/null || echo "0")
  if [[ "$FIRST_EPOCH" -gt 0 ]] && [[ "$LAST_EPOCH" -gt 0 ]]; then
    DURATION_SEC=$((LAST_EPOCH - FIRST_EPOCH))
    DURATION_MIN=$((DURATION_SEC / 60))
  fi
fi

# ── Generate text report ──
cat > "$OUTPUT_PATH" <<REPORT
══════════════════════════════════════
 FAE SESSION REPORT
 Generated: ${TIMESTAMP}
══════════════════════════════════════

 Runway:  ~${RUNWAY} turns until compaction
 Velocity: ${AVG_TOKENS} tokens/turn avg

 ── Savings ──────────────────────────
 Checkpoints saved:        ${CHECKPOINTS}
 Bash compressions:        ${COMPRESSIONS}  → ~${COMPRESSION_SAVINGS}K tokens
 Duplicate reads blocked:  ${DUPLICATES}  → ~${DUPLICATE_SAVINGS}K tokens
 Delta reads served:       ${DELTAS}
 Results aged:             ${AGED_RESULTS}
 Total estimated:          ~${TOTAL_SAVINGS}K tokens

 ── Drift Alerts ─────────────────────
 Alerts fired:             ${DRIFT_ALERTS}
 ├─ Read loop:             ${DRIFT_READ}
 ├─ Edit-revert:           ${DRIFT_EDIT}
 └─ Fail loop:             ${DRIFT_FAIL}

 Est. tokens saved by early intervention: ~${DRIFT_SAVINGS}K
 (avg 800 tokens/unproductive turn × turns avoided)

 ── Runway History ───────────────────
 Turns elapsed:            ${TURNS}
 Session duration:         ~${DURATION_MIN} min
 Avg tokens/turn:          ${AVG_TOKENS}

 ── Recommendations ──────────────────
$(if [[ "$RUNWAY" != "N/A" ]] && [[ "$RUNWAY" -lt 10 ]]; then
  echo " ⚠ Low runway. Run /fae:checkpoint then /compact."
fi)
$(if [[ "$DRIFT_ALERTS" -gt 3 ]]; then
  echo " ⚠ High drift count. Consider breaking task into smaller steps."
fi)
$(if [[ "$DUPLICATES" -gt 10 ]]; then
  echo " ⚠ Many duplicate reads blocked. Use Grep for targeted searches."
fi)
$(if [[ "$COMPRESSIONS" -eq 0 ]] && [[ "$TURNS" -gt 10 ]]; then
  echo " ℹ No compressions triggered. Bash output may be inflating context."
fi)

 Methodology: conservative multipliers.
 Bash=2K/ea, DupBlock=4K/ea, Drift=800tok/turn.

 ── Learnings ────────────────────────
$(# A9: prefer global XDG learnings, fall back to the legacy per-plugin path.
LEARNINGS_LOCAL="${PLUGINS_DIR}/context-guard/state/learnings.json"
(
  FAE_INIT_CWD="$PLUGINS_DIR"
  _si="$(dirname "$0")/session-init.sh"
  [[ -f "$_si" ]] && source "$_si" >/dev/null 2>&1 || true
  if [[ -n "${FAE_GLOBAL_DATA_DIR:-}" ]] && [[ -f "${FAE_GLOBAL_DATA_DIR}/learnings.json" ]]; then
    printf "%s" "${FAE_GLOBAL_DATA_DIR}/learnings.json"
  else
    printf "%s" "$LEARNINGS_LOCAL"
  fi
) > /tmp/fae-learnings-path.$$ 2>/dev/null
LEARNINGS_JSON=$(cat /tmp/fae-learnings-path.$$ 2>/dev/null)
rm -f /tmp/fae-learnings-path.$$
[[ -z "$LEARNINGS_JSON" ]] && LEARNINGS_JSON="$LEARNINGS_LOCAL"
if [[ -f "$LEARNINGS_JSON" ]] && jq empty "$LEARNINGS_JSON" >/dev/null 2>&1; then
  LEARN_SESSIONS=$(jq -r '.sessions_recorded // 0' "$LEARNINGS_JSON")
  echo " Sessions recorded:       ${LEARN_SESSIONS}"
  # Top 3 strategies by rate
  TOP_STRATS=$(jq -r '.strategy_rates // {} | to_entries | sort_by(-.value.rate) | .[:3][] | " \(.key): \(.value.rate * 100 | floor)% success (\(.value.fires) fires)"' "$LEARNINGS_JSON" 2>/dev/null)
  if [[ -n "$TOP_STRATS" ]]; then
    echo " Top strategies:"
    echo "$TOP_STRATS"
  fi
  # Active alerts
  LEARN_ALERTS=$(jq -r '.alerts // [] | .[]' "$LEARNINGS_JSON" 2>/dev/null)
  if [[ -n "$LEARN_ALERTS" ]]; then
    echo " Active alerts:"
    echo "$LEARN_ALERTS" | while read -r alert; do echo "   - $alert"; done
  fi
else
  echo " No learnings yet. Will accumulate after sessions."
fi)
══════════════════════════════════════
REPORT

echo "$OUTPUT_PATH"

# ── Update learnings (Bayesian Strategy Accumulation) ──
LEARNINGS_SCRIPT="$(cd "$(dirname "$0")" && pwd)/learnings.sh"
if [[ -f "$LEARNINGS_SCRIPT" ]]; then
  bash "$LEARNINGS_SCRIPT" "$PLUGINS_DIR" >/dev/null 2>/dev/null || true
fi

# ── Generate HTML → PDF report (Wixie pattern) ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PDF_SCRIPT="${SCRIPT_DIR}/report-pdf.py"
PDF_PATH="${OUTPUT_PATH%.txt}.pdf"

if [[ -f "$PDF_SCRIPT" ]]; then
  # Try python, python3, py in order
  PYTHON_CMD=""
  for cmd in python python3 py; do
    if command -v "$cmd" >/dev/null 2>&1; then
      PYTHON_CMD="$cmd"
      break
    fi
  done

  if [[ -n "$PYTHON_CMD" ]]; then
    PDF_RESULT=$("$PYTHON_CMD" "$PDF_SCRIPT" "$PLUGINS_DIR" "$PDF_PATH" 2>/dev/null) || true
    if [[ -n "$PDF_RESULT" ]] && [[ -f "$PDF_RESULT" ]]; then
      echo "$PDF_RESULT"
    fi
  fi
fi

exit 0
