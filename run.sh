#!/usr/bin/env bash
# Orchestrator: find latest traces for all scenarios, judge each, produce report
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
TRACES_DIR="${SCRIPT_DIR}/traces"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
JUDGMENT_DIR="${SCRIPT_DIR}/judgments/${TIMESTAMP}"

mkdir -p "${JUDGMENT_DIR}"

SATISFIED=0
UNSATISFIED=0
INSUFFICIENT=0
TOTAL=0
CRITICAL_FAILURES=()

echo "========================================="
echo "  Satisfaction Harness — Full Run"
echo "  $(date)"
echo "========================================="
echo ""

for SCENARIO_FILE in "${SCENARIOS_DIR}"/*.md; do
  SCENARIO_ID="$(basename "${SCENARIO_FILE}" .md)"
  TRACES_BASE="${TRACES_DIR}/${SCENARIO_ID}"

  echo "--- Scenario: ${SCENARIO_ID} ---"

  if [ ! -d "${TRACES_BASE}" ]; then
    echo "  SKIP: No traces found"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  TRACE_DIR="$(ls -1d "${TRACES_BASE}"/*/ 2>/dev/null | sort | tail -1)"
  if [ -z "${TRACE_DIR}" ]; then
    echo "  SKIP: No trace directories found"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  TRACE_DIR="${TRACE_DIR%/}"

  if [ ! -f "${TRACE_DIR}/trace-summary.md" ]; then
    echo "  SKIP: No trace-summary.md in ${TRACE_DIR}"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  echo "  Trace: ${TRACE_DIR}"

  # Read scenario and trace
  SCENARIO_CONTENT="$(cat "${SCENARIO_FILE}")"
  TRACE_CONTENT="$(cat "${TRACE_DIR}/trace-summary.md")"

  JUDGE_INPUT="# Scenario Under Test

${SCENARIO_CONTENT}

# Evidence Report (Trace Summary)

${TRACE_CONTENT}

# Your Task

Evaluate the trace evidence against each satisfaction criterion listed in the scenario. Check for any anti-patterns. Return your judgment as JSON matching the required schema.

The scenario_id is: ${SCENARIO_ID}"

  claude -p "${JUDGE_INPUT}" \
    --output-format json \
    --system-prompt-file "${SCRIPT_DIR}/judge-prompt.md" \
    --json-schema "$(cat "${SCRIPT_DIR}/judgment-schema.json")" \
    --allowedTools "" \
    > "${JUDGMENT_DIR}/${SCENARIO_ID}.json"

  # Extract verdict
  VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['verdict'])" "${JUDGMENT_DIR}/${SCENARIO_ID}.json" 2>/dev/null || echo "unknown")
  SCORE=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['satisfaction_score'])" "${JUDGMENT_DIR}/${SCENARIO_ID}.json" 2>/dev/null || echo "0")

  echo "  Verdict: ${VERDICT} (score: ${SCORE})"

  case "${VERDICT}" in
    satisfied)
      SATISFIED=$((SATISFIED + 1))
      ;;
    unsatisfied)
      UNSATISFIED=$((UNSATISFIED + 1))
      # Check if this scenario is critical priority
      PRIORITY=$(sed -n 's/^priority: *//p' "${SCENARIO_FILE}" | tr -d '[:space:]')
      if [ "${PRIORITY}" = "critical" ]; then
        CRITICAL_FAILURES+=("${SCENARIO_ID}")
      fi
      ;;
    insufficient_evidence)
      INSUFFICIENT=$((INSUFFICIENT + 1))
      ;;
    *)
      INSUFFICIENT=$((INSUFFICIENT + 1))
      ;;
  esac

  TOTAL=$((TOTAL + 1))
  echo ""
done

# Build report
CRITICAL_JSON="[]"
if [ ${#CRITICAL_FAILURES[@]} -gt 0 ]; then
  CRITICAL_JSON=$(printf '%s\n' "${CRITICAL_FAILURES[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin]))")
fi

REPORT=$(cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "total": ${TOTAL},
  "satisfied": ${SATISFIED},
  "unsatisfied": ${UNSATISFIED},
  "insufficient_evidence": ${INSUFFICIENT},
  "critical_failures": ${CRITICAL_JSON},
  "pass": $([ ${UNSATISFIED} -eq 0 ] && [ ${#CRITICAL_FAILURES[@]} -eq 0 ] && echo "true" || echo "false")
}
EOF
)

echo "${REPORT}" | python3 -m json.tool > "${JUDGMENT_DIR}/report.json"

echo "========================================="
echo "  Results: ${SATISFIED}/${TOTAL} satisfied"
echo "  Unsatisfied: ${UNSATISFIED}"
echo "  Insufficient evidence: ${INSUFFICIENT}"
if [ ${#CRITICAL_FAILURES[@]} -gt 0 ]; then
  echo "  CRITICAL FAILURES: ${CRITICAL_FAILURES[*]}"
fi
echo "  Report: ${JUDGMENT_DIR}/report.json"
echo "========================================="

# Exit with non-zero if any critical failures
if [ ${#CRITICAL_FAILURES[@]} -gt 0 ]; then
  exit 1
fi
