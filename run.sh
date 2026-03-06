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

echo ""
echo "=========================================="
echo "  SATISFACTION HARNESS — Full Run"
echo "  $(date)"
echo "=========================================="
echo ""

# Count scenarios
SCENARIO_COUNT=0
for _ in "${SCENARIOS_DIR}"/*.md; do SCENARIO_COUNT=$((SCENARIO_COUNT + 1)); done
echo "  Scenarios found: ${SCENARIO_COUNT}"
echo "  Judgments dir:   ${JUDGMENT_DIR}"
echo ""

SCENARIO_NUM=0

for SCENARIO_FILE in "${SCENARIOS_DIR}"/*.md; do
  SCENARIO_ID="$(basename "${SCENARIO_FILE}" .md)"
  TRACES_BASE="${TRACES_DIR}/${SCENARIO_ID}"
  SCENARIO_NUM=$((SCENARIO_NUM + 1))
  PRIORITY=$(sed -n 's/^priority: *//p' "${SCENARIO_FILE}" | tr -d '[:space:]')

  echo "------------------------------------------"
  echo "  [${SCENARIO_NUM}/${SCENARIO_COUNT}] ${SCENARIO_ID}"
  echo "  Priority: ${PRIORITY:-normal}"
  echo "------------------------------------------"

  # --- Find trace ---
  if [ ! -d "${TRACES_BASE}" ]; then
    echo "  SKIP — no traces captured yet"
    echo "  Run: bash capture-agent.sh ${SCENARIO_ID}"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    echo ""
    continue
  fi

  TRACE_DIR="$(ls -1d "${TRACES_BASE}"/*/ 2>/dev/null | sort | tail -1)"
  if [ -z "${TRACE_DIR}" ]; then
    echo "  SKIP — no trace directories found"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    echo ""
    continue
  fi

  TRACE_DIR="${TRACE_DIR%/}"

  if [ ! -f "${TRACE_DIR}/trace-summary.md" ]; then
    echo "  SKIP — no trace-summary.md in trace dir"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    echo ""
    continue
  fi

  TRACE_LINES=$(wc -l < "${TRACE_DIR}/trace-summary.md")
  echo "  Trace: $(basename "${TRACE_DIR}") (${TRACE_LINES} lines)"

  # --- Judge ---
  echo "  Judging... (sending to Claude, no tools)"

  SCENARIO_CONTENT="$(cat "${SCENARIO_FILE}")"
  TRACE_CONTENT="$(cat "${TRACE_DIR}/trace-summary.md")"

  JUDGE_INPUT="# Scenario Under Test

${SCENARIO_CONTENT}

# Evidence Report (Trace Summary)

${TRACE_CONTENT}

# Your Task

Evaluate the trace evidence against each satisfaction criterion listed in the scenario. Check for any anti-patterns.

IMPORTANT: Your entire response must be a single valid JSON object — no prose, no markdown, no explanation. Output ONLY the JSON object matching this schema:

{
  \"scenario_id\": \"${SCENARIO_ID}\",
  \"verdict\": \"satisfied|unsatisfied|insufficient_evidence\",
  \"satisfaction_score\": 0.0-1.0,
  \"criteria_results\": [{\"criterion\": \"id\", \"met\": true/false/null, \"evidence\": \"specific citation\"}],
  \"anti_patterns_detected\": [\"description\"],
  \"notes\": \"reasoning\"
}"

  RAW_OUTPUT="${JUDGMENT_DIR}/${SCENARIO_ID}.raw.json"
  CLEAN_OUTPUT="${JUDGMENT_DIR}/${SCENARIO_ID}.json"
  MAX_RETRIES=2
  CURRENT_PROMPT="${JUDGE_INPUT}"
  JUDGE_OK=false

  for ATTEMPT in $(seq 0 "${MAX_RETRIES}"); do
    if [ "${ATTEMPT}" -gt 0 ]; then
      echo "  Retry ${ATTEMPT}/${MAX_RETRIES} — feeding validation error back to Claude..."
    fi

    # Run from /tmp to prevent Claude from reading CLAUDE.md or repo files (anti-contamination)
    (cd /tmp && claude -p "${CURRENT_PROMPT}" \
      --output-format json \
      --system-prompt-file "${SCRIPT_DIR}/judge-prompt.md" \
      --json-schema "$(cat "${SCRIPT_DIR}/judgment-schema.json")" \
      --allowedTools "") \
      > "${RAW_OUTPUT}"

    EXTRACT_RESULT=$(python3 "${SCRIPT_DIR}/extract-judgment.py" "${RAW_OUTPUT}" "${CLEAN_OUTPUT}" 2>&1)

    if [ $? -eq 0 ]; then
      if [ "${ATTEMPT}" -gt 0 ]; then
        echo "  Validation passed on retry ${ATTEMPT}"
      fi
      JUDGE_OK=true
      break
    fi

    if [ "${ATTEMPT}" -lt "${MAX_RETRIES}" ]; then
      INVALID_FILE="${CLEAN_OUTPUT}.invalid.json"
      INVALID_JSON=""
      if [ -f "${INVALID_FILE}" ]; then
        INVALID_JSON="$(cat "${INVALID_FILE}")"
      fi

      CURRENT_PROMPT="Your previous JSON output failed schema validation.

ERROR: ${EXTRACT_RESULT}

Your previous output:
${INVALID_JSON}

The JSON schema requires:
$(cat "${SCRIPT_DIR}/judgment-schema.json")

Fix the JSON to pass validation. Output ONLY the corrected JSON object — no prose, no markdown fences, no explanation."

      echo "  Validation failed, retrying with error feedback..."
    fi
  done

  if [ "${JUDGE_OK}" != "true" ]; then
    echo "  ERROR — failed to get valid judgment after $((MAX_RETRIES + 1)) attempts"
    echo "  Raw output: ${RAW_OUTPUT}"
    INSUFFICIENT=$((INSUFFICIENT + 1))
    TOTAL=$((TOTAL + 1))
    echo ""
    continue
  fi

  # --- Display results ---
  VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['verdict'])" "${CLEAN_OUTPUT}")
  SCORE=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['satisfaction_score'])" "${CLEAN_OUTPUT}")
  CRITERIA_COUNT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['criteria_results']))" "${CLEAN_OUTPUT}")
  CRITERIA_MET=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for c in d['criteria_results'] if c.get('met') is True))" "${CLEAN_OUTPUT}")

  echo ""
  echo "  Verdict:      ${VERDICT}"
  echo "  Score:        ${SCORE}"
  echo "  Criteria met: ${CRITERIA_MET}/${CRITERIA_COUNT}"

  # Show per-criterion one-liners
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for c in d['criteria_results']:
    status = 'PASS' if c.get('met') is True else ('FAIL' if c.get('met') is False else '????')
    print(f'    {status}  {c[\"criterion\"]}')
" "${CLEAN_OUTPUT}"

  case "${VERDICT}" in
    satisfied)
      SATISFIED=$((SATISFIED + 1))
      ;;
    unsatisfied)
      UNSATISFIED=$((UNSATISFIED + 1))
      if [ "${PRIORITY}" = "critical" ]; then
        CRITICAL_FAILURES+=("${SCENARIO_ID}")
        echo ""
        echo "  *** CRITICAL FAILURE ***"
      fi
      # Append failed criteria to failures JSONL
      python3 -c "
import json, sys
judgment = json.load(open(sys.argv[1]))
scenario_file = sys.argv[2]
for c in judgment['criteria_results']:
    if c.get('met') is not True:
        line = {
            'scenario_id': judgment['scenario_id'],
            'criterion': c['criterion'],
            'met': c['met'],
            'evidence': c['evidence'],
            'anti_patterns': judgment.get('anti_patterns_detected', []),
            'satisfaction_score': judgment['satisfaction_score'],
            'priority': sys.argv[3],
            'scenario_file': scenario_file,
            'notes': judgment.get('notes', '')
        }
        print(json.dumps(line))
" "${CLEAN_OUTPUT}" "${SCENARIO_FILE}" "${PRIORITY:-normal}" >> "${JUDGMENT_DIR}/failures.jsonl"
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

# --- Build report ---
CRITICAL_JSON="[]"
if [ ${#CRITICAL_FAILURES[@]} -gt 0 ]; then
  CRITICAL_JSON=$(printf '%s\n' "${CRITICAL_FAILURES[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin]))")
fi

PASS=$([ ${UNSATISFIED} -eq 0 ] && [ ${#CRITICAL_FAILURES[@]} -eq 0 ] && echo "true" || echo "false")

REPORT=$(cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "total": ${TOTAL},
  "satisfied": ${SATISFIED},
  "unsatisfied": ${UNSATISFIED},
  "insufficient_evidence": ${INSUFFICIENT},
  "critical_failures": ${CRITICAL_JSON},
  "pass": ${PASS}
}
EOF
)

echo "${REPORT}" | python3 -m json.tool > "${JUDGMENT_DIR}/report.json"

echo "=========================================="
echo "  RESULTS SUMMARY"
echo "=========================================="
echo ""
echo "  Total scenarios: ${TOTAL}"
echo "  Satisfied:       ${SATISFIED}"
echo "  Unsatisfied:     ${UNSATISFIED}"
echo "  No evidence:     ${INSUFFICIENT}"
echo ""
if [ "${PASS}" = "true" ]; then
  echo "  Overall: PASS"
else
  echo "  Overall: FAIL"
  if [ ${#CRITICAL_FAILURES[@]} -gt 0 ]; then
    echo "  Critical failures: ${CRITICAL_FAILURES[*]}"
  fi
fi
echo ""
echo "  Report:   ${JUDGMENT_DIR}/report.json"
if [ -f "${JUDGMENT_DIR}/failures.jsonl" ]; then
  FAILURE_COUNT=$(wc -l < "${JUDGMENT_DIR}/failures.jsonl")
  echo "  Failures: ${JUDGMENT_DIR}/failures.jsonl (${FAILURE_COUNT} items)"
fi
echo ""

# Exit with non-zero if any critical failures
if [ ${#CRITICAL_FAILURES[@]} -gt 0 ]; then
  exit 1
fi
