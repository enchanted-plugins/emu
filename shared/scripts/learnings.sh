#!/usr/bin/env bash
# Allay self-learning system — Bayesian Strategy Accumulation
# Logs session data, accumulates strategy success rates across sessions,
# detects patterns, persists to learnings.json.
# Not time-critical — called from report-gen.sh or save-checkpoint.sh.
#
# Algorithm: Bayesian Strategy Accumulation
#   r_new = alpha * s_current + (1 - alpha) * r_prior
#   alpha = 0.3 (learning rate)
#
# Usage: bash learnings.sh <plugins_dir>
#   plugins_dir: path to the plugins/ directory

set +e

# ── Check jq availability ──
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PLUGINS_DIR="${1:-}"

if [[ -z "$PLUGINS_DIR" ]]; then
  echo "Usage: learnings.sh <plugins_dir>" >&2
  exit 1
fi

# Resolve shared dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/.."

# shellcheck source=../constants.sh
source "${SHARED_DIR}/constants.sh"
# shellcheck source=../metrics.sh
source "${SHARED_DIR}/metrics.sh"

# ── Metrics files ──
CG_METRICS="${PLUGINS_DIR}/context-guard/state/metrics.jsonl"
TS_METRICS="${PLUGINS_DIR}/token-saver/state/metrics.jsonl"
SK_METRICS="${PLUGINS_DIR}/state-keeper/state/metrics.jsonl"

# ── Learnings file (stored in context-guard state — the "brain" of Allay) ──
LEARNINGS_FILE="${PLUGINS_DIR}/context-guard/state/learnings.json"
LEARNINGS_TMP="${LEARNINGS_FILE}.tmp"
LEARNINGS_LOCK="${LEARNINGS_FILE}${ALLAY_LOCK_SUFFIX}"

# ── EMA learning rate ──
ALPHA="0.3"

# ── Helper: safe count ──
count_events() {
  local file="$1"
  local pattern="$2"
  local count=0
  if [[ -f "$file" ]]; then
    count=$(grep -c "$pattern" "$file" 2>/dev/null || true)
  fi
  # Ensure numeric
  count=$(echo "$count" | tr -d '[:space:]')
  echo "${count:-0}"
}

# ── Helper: count by rule ──
count_by_rule() {
  local file="$1"
  local rule="$2"
  local count=0
  if [[ -f "$file" ]]; then
    count=$(grep '"bash_compressed"' "$file" 2>/dev/null | grep -c "\"${rule}\"" 2>/dev/null || true)
  fi
  count=$(echo "$count" | tr -d '[:space:]')
  echo "${count:-0}"
}

# ── Helper: EMA calculation ──
ema() {
  local alpha="$1" current="$2" prior="$3"
  jq -n --argjson a "$alpha" --argjson c "$current" --argjson p "$prior" \
    '($a * $c) + ((1 - $a) * $p)' 2>/dev/null || echo "$current"
}

# ── Helper: read JSON field with default ──
json_field() {
  local json="$1" field="$2" default="$3"
  local val
  val=$(printf "%s" "$json" | jq -r ".$field" 2>/dev/null || true)
  if [[ -z "$val" ]] || [[ "$val" == "null" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

# ── Gather current session data ──
TURNS=$(count_events "$CG_METRICS" '"event":"turn"')
COMPRESSIONS=$(count_events "$TS_METRICS" '"bash_compressed"')
DUPLICATES=$(count_events "$TS_METRICS" '"duplicate_blocked"')
DELTAS=$(count_events "$TS_METRICS" '"delta_read"')
DRIFT_TOTAL=$(count_events "$CG_METRICS" '"drift_detected"')
DRIFT_READ=$(count_events "$CG_METRICS" '"read_loop"')
DRIFT_EDIT=$(count_events "$CG_METRICS" '"edit_revert"')
DRIFT_FAIL=$(count_events "$CG_METRICS" '"test_fail_loop"')

# If no data at all, exit silently
if [[ "$TURNS" -eq 0 ]] && [[ "$COMPRESSIONS" -eq 0 ]]; then
  exit 0
fi

# ── Estimated tokens saved (conservative multipliers) ──
TOKENS_SAVED=$(( COMPRESSIONS * 2000 + DUPLICATES * 4000 + DRIFT_TOTAL * 800 ))

# ── Count per compression rule ──
RULES=("test_tail" "pytest_filter" "gotest_filter" "jvm_test_filter" "dotnet_filter" \
       "install_filter" "cargo_filter" "make_filter" "docker_build_filter" \
       "terraform_plan_filter" "eslint_filter" "tsc_filter" "git_log_trim" \
       "find_head" "cat_head")

RULE_COUNTS_JSON="{"
FIRST=true
for rule in "${RULES[@]}"; do
  count=$(count_by_rule "$TS_METRICS" "$rule")
  if [[ "$FIRST" == "true" ]]; then
    FIRST=false
  else
    RULE_COUNTS_JSON+=","
  fi
  RULE_COUNTS_JSON+="\"${rule}\":${count}"
done
RULE_COUNTS_JSON+="}"

# ── Read existing learnings (or initialize) ──
EXISTING="{}"
if [[ -f "$LEARNINGS_FILE" ]]; then
  if jq empty "$LEARNINGS_FILE" >/dev/null 2>&1; then
    EXISTING=$(cat "$LEARNINGS_FILE")
  fi
fi

PREV_SESSIONS=$(json_field "$EXISTING" "sessions_recorded" "0")
NEW_SESSIONS=$((PREV_SESSIONS + 1))

# ── Update strategy rates using EMA ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TODAY=$(date -u +"%Y-%m-%d")

# Build updated rates: for each rule, compute EMA of success
# Accumulate as a jq-constructed object by piping through jq iteratively
UPDATED_RATES="{}"
for rule in "${RULES[@]}"; do
  count=$(count_by_rule "$TS_METRICS" "$rule")
  success=0
  [[ "$count" -gt 0 ]] && success=1

  # Get prior rate and fires from existing learnings
  prior_rate=$(printf "%s" "$EXISTING" | jq -r ".strategy_rates.${rule}.rate" 2>/dev/null || true)
  [[ -z "$prior_rate" ]] || [[ "$prior_rate" == "null" ]] && prior_rate="0.5"

  prior_fires=$(printf "%s" "$EXISTING" | jq -r ".strategy_rates.${rule}.fires" 2>/dev/null || true)
  [[ -z "$prior_fires" ]] || [[ "$prior_fires" == "null" ]] && prior_fires="0"

  new_rate=$(ema "$ALPHA" "$success" "$prior_rate")
  new_fires=$((prior_fires + count))

  UPDATED_RATES=$(printf "%s" "$UPDATED_RATES" | jq -c \
    --arg rule "$rule" \
    --argjson rate "$new_rate" \
    --argjson fires "$new_fires" \
    --arg last "$TODAY" \
    '.[$rule] = {rate: $rate, fires: $fires, last_session: $last}' 2>/dev/null || echo "$UPDATED_RATES")
done

# ── Update drift patterns using EMA ──
# Pre-compute each value in bash, build JSON with jq -n
PREV_READ_FREQ=$(printf "%s" "$EXISTING" | jq -r '.drift_patterns.read_loop.frequency' 2>/dev/null || true)
[[ -z "$PREV_READ_FREQ" ]] || [[ "$PREV_READ_FREQ" == "null" ]] && PREV_READ_FREQ="0"
PREV_READ_RES=$(printf "%s" "$EXISTING" | jq -r '.drift_patterns.read_loop.resolved_rate' 2>/dev/null || true)
[[ -z "$PREV_READ_RES" ]] || [[ "$PREV_READ_RES" == "null" ]] && PREV_READ_RES="0.5"

PREV_EDIT_FREQ=$(printf "%s" "$EXISTING" | jq -r '.drift_patterns.edit_revert.frequency' 2>/dev/null || true)
[[ -z "$PREV_EDIT_FREQ" ]] || [[ "$PREV_EDIT_FREQ" == "null" ]] && PREV_EDIT_FREQ="0"
PREV_EDIT_RES=$(printf "%s" "$EXISTING" | jq -r '.drift_patterns.edit_revert.resolved_rate' 2>/dev/null || true)
[[ -z "$PREV_EDIT_RES" ]] || [[ "$PREV_EDIT_RES" == "null" ]] && PREV_EDIT_RES="0.5"

PREV_FAIL_FREQ=$(printf "%s" "$EXISTING" | jq -r '.drift_patterns.test_fail_loop.frequency' 2>/dev/null || true)
[[ -z "$PREV_FAIL_FREQ" ]] || [[ "$PREV_FAIL_FREQ" == "null" ]] && PREV_FAIL_FREQ="0"
PREV_FAIL_RES=$(printf "%s" "$EXISTING" | jq -r '.drift_patterns.test_fail_loop.resolved_rate' 2>/dev/null || true)
[[ -z "$PREV_FAIL_RES" ]] || [[ "$PREV_FAIL_RES" == "null" ]] && PREV_FAIL_RES="0.5"

NEW_READ_FREQ=$(ema "$ALPHA" "$DRIFT_READ" "$PREV_READ_FREQ")
NEW_EDIT_FREQ=$(ema "$ALPHA" "$DRIFT_EDIT" "$PREV_EDIT_FREQ")
NEW_FAIL_FREQ=$(ema "$ALPHA" "$DRIFT_FAIL" "$PREV_FAIL_FREQ")

UPDATED_DRIFT=$(jq -cn \
  --argjson rf "$NEW_READ_FREQ" --argjson rr "$PREV_READ_RES" \
  --argjson ef "$NEW_EDIT_FREQ" --argjson er "$PREV_EDIT_RES" \
  --argjson ff "$NEW_FAIL_FREQ" --argjson fr "$PREV_FAIL_RES" \
  '{read_loop:{frequency:$rf,resolved_rate:$rr},edit_revert:{frequency:$ef,resolved_rate:$er},test_fail_loop:{frequency:$ff,resolved_rate:$fr}}' \
  2>/dev/null)

if [[ -z "$UPDATED_DRIFT" ]] || [[ "$UPDATED_DRIFT" == "null" ]]; then
  UPDATED_DRIFT='{"read_loop":{"frequency":0,"resolved_rate":0.5},"edit_revert":{"frequency":0,"resolved_rate":0.5},"test_fail_loop":{"frequency":0,"resolved_rate":0.5}}'
fi

# ── Detect alert patterns ──
# Chronic drift: frequency > 3 per session on average
ALERTS="[]"
ALERT_LIST=""
if jq -e ".read_loop.frequency > 3" <<< "$UPDATED_DRIFT" >/dev/null 2>&1; then
  ALERT_LIST+="\"chronic:read_loop\","
fi
if jq -e ".edit_revert.frequency > 3" <<< "$UPDATED_DRIFT" >/dev/null 2>&1; then
  ALERT_LIST+="\"chronic:edit_revert\","
fi
if jq -e ".test_fail_loop.frequency > 3" <<< "$UPDATED_DRIFT" >/dev/null 2>&1; then
  ALERT_LIST+="\"chronic:test_fail_loop\","
fi
ALERT_LIST="${ALERT_LIST%,}"
ALERTS="[${ALERT_LIST}]"

# ── Compute running averages ──
PREV_AVG_SAVED=$(json_field "$EXISTING" "avg_tokens_saved" "0")
PREV_AVG_TURNS=$(json_field "$EXISTING" "avg_turns" "0")

NEW_AVG_SAVED=$(ema "$ALPHA" "$TOKENS_SAVED" "$PREV_AVG_SAVED")
NEW_AVG_TURNS=$(ema "$ALPHA" "$TURNS" "$PREV_AVG_TURNS")

# ── Build final learnings JSON ──
LEARNINGS=$(jq -cn \
  --argjson version 1 \
  --arg updated "$TIMESTAMP" \
  --argjson sessions "$NEW_SESSIONS" \
  --argjson strategy_rates "$UPDATED_RATES" \
  --argjson drift_patterns "$UPDATED_DRIFT" \
  --argjson alerts "$ALERTS" \
  --argjson avg_tokens_saved "$NEW_AVG_SAVED" \
  --argjson avg_turns "$NEW_AVG_TURNS" \
  '{
    version: $version,
    updated: $updated,
    sessions_recorded: $sessions,
    strategy_rates: $strategy_rates,
    drift_patterns: $drift_patterns,
    alerts: $alerts,
    avg_tokens_saved: $avg_tokens_saved,
    avg_turns: $avg_turns
  }' 2>/dev/null)

if [[ -z "$LEARNINGS" ]] || ! printf "%s" "$LEARNINGS" | jq empty >/dev/null 2>&1; then
  exit 0
fi

# ── Write atomically with lock ──
acquire_lock "$LEARNINGS_LOCK" || exit 0

mkdir -p "$(dirname "$LEARNINGS_FILE")"
printf "%s\n" "$LEARNINGS" > "$LEARNINGS_TMP"
mv "$LEARNINGS_TMP" "$LEARNINGS_FILE"

release_lock "$LEARNINGS_LOCK"

# ── Output summary as JSONL ──
STRATEGIES_TRACKED=$(printf "%s" "$UPDATED_RATES" | jq 'length' 2>/dev/null || echo "0")

jq -cn \
  --arg event "learning_updated" \
  --arg ts "$TIMESTAMP" \
  --argjson sessions "$NEW_SESSIONS" \
  --argjson strategies "${STRATEGIES_TRACKED:-0}" \
  '{event:$event, ts:$ts, sessions:$sessions, strategies_tracked:$strategies}'

exit 0
