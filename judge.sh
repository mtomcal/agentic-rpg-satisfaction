#!/usr/bin/env bash
# Judge a single scenario's trace against its satisfaction criteria
set -euo pipefail

SCENARIO_ID="${1:?Usage: judge.sh <scenario-id> [trace-dir]}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRITERIA_FILE="${SCRIPT_DIR}/scenarios/${SCENARIO_ID}.criteria.md"

echo ""
echo "========================================"
echo "  JUDGE — Single Scenario"
echo "  $(date)"
echo "========================================"
echo ""

# --- Validate criteria file ---
if [ ! -f "${CRITERIA_FILE}" ]; then
  echo "  ERROR: Criteria not found: ${CRITERIA_FILE}"
  echo "  Available scenarios:"
  for f in "${SCRIPT_DIR}/scenarios"/*.criteria.md; do
    echo "    - $(basename "$f" .criteria.md)"
  done
  exit 1
fi

echo "  Scenario: ${SCENARIO_ID}"

# --- Find trace directory ---
if [ -n "${2:-}" ]; then
  TRACE_DIR="$2"
  echo "  Trace:    ${TRACE_DIR} (provided)"
else
  TRACES_BASE="${SCRIPT_DIR}/traces/${SCENARIO_ID}"
  if [ ! -d "${TRACES_BASE}" ]; then
    echo ""
    echo "  ERROR: No traces found for scenario '${SCENARIO_ID}'"
    echo "  Run a capture first:"
    echo "    bash capture-agent.sh ${SCENARIO_ID}"
    echo "    bash capture-manual.sh <recording> ${SCENARIO_ID}"
    exit 1
  fi
  TRACE_DIR="$(ls -1d "${TRACES_BASE}"/*/ 2>/dev/null | sort | tail -1)"
  if [ -z "${TRACE_DIR}" ]; then
    echo ""
    echo "  ERROR: No trace directories in ${TRACES_BASE}"
    exit 1
  fi
  TRACE_DIR="${TRACE_DIR%/}"
  echo "  Trace:    ${TRACE_DIR} (latest)"
fi

if [ ! -f "${TRACE_DIR}/trace-summary.md" ]; then
  echo ""
  echo "  ERROR: No trace-summary.md in ${TRACE_DIR}"
  exit 1
fi

TRACE_LINES=$(wc -l < "${TRACE_DIR}/trace-summary.md")
TRACE_SIZE=$(wc -c < "${TRACE_DIR}/trace-summary.md")
echo "  Evidence: ${TRACE_LINES} lines, ${TRACE_SIZE} bytes"

# --- Prepare output ---
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
JUDGMENT_DIR="${SCRIPT_DIR}/judgments/${TIMESTAMP}"
mkdir -p "${JUDGMENT_DIR}"

echo ""
echo "  [1/3] Assembling judge input..."

CRITERIA_CONTENT="$(cat "${CRITERIA_FILE}")"
TRACE_CONTENT="$(cat "${TRACE_DIR}/trace-summary.md")"

JUDGE_INPUT="# Judgment Criteria

${CRITERIA_CONTENT}

# Evidence Report (Trace Summary)

${TRACE_CONTENT}

# Your Task

Evaluate the trace evidence against each satisfaction criterion. Check for any anti-patterns. The evidence was gathered by a separate observer — assess it on its own merits.

IMPORTANT: Your entire response must be a single valid JSON object — no prose, no markdown, no explanation. Output ONLY the JSON object matching this schema:

{
  \"scenario_id\": \"${SCENARIO_ID}\",
  \"verdict\": \"satisfied|unsatisfied|insufficient_evidence\",
  \"satisfaction_score\": 0.0-1.0,
  \"criteria_results\": [{\"criterion\": \"id\", \"met\": true/false/null, \"evidence\": \"specific citation\"}],
  \"anti_patterns_detected\": [\"description\"],
  \"notes\": \"reasoning\"
}"

echo "  [2/3] Sending to Claude judge (no tools, schema-enforced)..."
echo "         System prompt: judge-prompt.md"
echo "         Schema:        judgment-schema.json"

RAW_OUTPUT="${JUDGMENT_DIR}/${SCENARIO_ID}.raw.json"
CLEAN_OUTPUT="${JUDGMENT_DIR}/${SCENARIO_ID}.json"
MAX_RETRIES=2
CURRENT_PROMPT="${JUDGE_INPUT}"

for ATTEMPT in $(seq 0 "${MAX_RETRIES}"); do
  if [ "${ATTEMPT}" -gt 0 ]; then
    echo "  [2/3] Retry ${ATTEMPT}/${MAX_RETRIES} — feeding validation error back to Claude..."
  fi

  # Run from /tmp to prevent Claude from reading CLAUDE.md or repo files (anti-contamination)
  (cd /tmp && claude -p "${CURRENT_PROMPT}" \
    --output-format json \
    --system-prompt-file "${SCRIPT_DIR}/judge-prompt.md" \
    --json-schema "$(cat "${SCRIPT_DIR}/judgment-schema.json")" \
    --allowedTools "") \
    > "${RAW_OUTPUT}"

  echo "  [3/3] Extracting and validating judgment JSON..."

  EXTRACT_RESULT=$(python3 "${SCRIPT_DIR}/extract-judgment.py" "${RAW_OUTPUT}" "${CLEAN_OUTPUT}" 2>&1)

  if [ $? -eq 0 ]; then
    if [ "${ATTEMPT}" -gt 0 ]; then
      echo "         Validation passed on retry ${ATTEMPT}"
    fi
    break
  fi

  if [ "${ATTEMPT}" -lt "${MAX_RETRIES}" ]; then
    # Read the invalid JSON that was saved for debugging
    INVALID_FILE="${CLEAN_OUTPUT}.invalid.json"
    INVALID_JSON=""
    if [ -f "${INVALID_FILE}" ]; then
      INVALID_JSON="$(cat "${INVALID_FILE}")"
    fi

    # Build retry prompt with the error fed back
    CURRENT_PROMPT="Your previous JSON output failed schema validation.

ERROR: ${EXTRACT_RESULT}

Your previous output:
${INVALID_JSON}

The JSON schema requires:
$(cat "${SCRIPT_DIR}/judgment-schema.json")

Fix the JSON to pass validation. Output ONLY the corrected JSON object — no prose, no markdown fences, no explanation."

    echo "         Validation failed, will retry with error feedback"
  else
    echo ""
    echo "  ERROR: Failed to get valid judgment after $((MAX_RETRIES + 1)) attempts"
    echo "  ${EXTRACT_RESULT}"
    echo "  Raw output saved to: ${RAW_OUTPUT}"
    exit 1
  fi
done

# --- Print results ---
VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['verdict'])" "${CLEAN_OUTPUT}")
SCORE=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['satisfaction_score'])" "${CLEAN_OUTPUT}")
CRITERIA_COUNT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['criteria_results']))" "${CLEAN_OUTPUT}")
CRITERIA_MET=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for c in d['criteria_results'] if c.get('met') is True))" "${CLEAN_OUTPUT}")
ANTIPATTERNS=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['anti_patterns_detected']))" "${CLEAN_OUTPUT}")
NOTES=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('notes',''))" "${CLEAN_OUTPUT}")

echo ""
echo "========================================"
echo "  JUDGMENT RESULT"
echo "========================================"
echo ""
echo "  Verdict:      ${VERDICT}"
echo "  Score:        ${SCORE}"
echo "  Criteria met: ${CRITERIA_MET}/${CRITERIA_COUNT}"
echo "  Anti-patterns: ${ANTIPATTERNS} detected"
echo ""

# Show per-criterion results
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for c in d['criteria_results']:
    status = 'PASS' if c.get('met') is True else ('FAIL' if c.get('met') is False else '????')
    print(f'  {status}  {c[\"criterion\"]}')
    if c.get('met') is not True:
        evidence = c.get('evidence', '')
        if evidence:
            print(f'         {evidence[:100]}...' if len(evidence) > 100 else f'         {evidence}')
" "${CLEAN_OUTPUT}"

if [ -n "${NOTES}" ]; then
  echo ""
  echo "  Notes: ${NOTES}"
fi

echo ""
echo "  Output: ${CLEAN_OUTPUT}"
echo ""
