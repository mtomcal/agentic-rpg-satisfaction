#!/usr/bin/env bash
# Judge a single scenario's trace against its satisfaction criteria
set -euo pipefail

SCENARIO_ID="${1:?Usage: judge.sh <scenario-id> [trace-dir]}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIO_FILE="${SCRIPT_DIR}/scenarios/${SCENARIO_ID}.md"

if [ ! -f "${SCENARIO_FILE}" ]; then
  echo "Error: Scenario file not found: ${SCENARIO_FILE}"
  exit 1
fi

# Find the trace directory — use provided path or find the latest
if [ -n "${2:-}" ]; then
  TRACE_DIR="$2"
else
  TRACES_BASE="${SCRIPT_DIR}/traces/${SCENARIO_ID}"
  if [ ! -d "${TRACES_BASE}" ]; then
    echo "Error: No traces found for scenario ${SCENARIO_ID}"
    exit 1
  fi
  TRACE_DIR="$(ls -1d "${TRACES_BASE}"/*/ 2>/dev/null | sort | tail -1)"
  if [ -z "${TRACE_DIR}" ]; then
    echo "Error: No trace directories found in ${TRACES_BASE}"
    exit 1
  fi
fi

TRACE_DIR="${TRACE_DIR%/}"

if [ ! -f "${TRACE_DIR}/trace-summary.md" ]; then
  echo "Error: No trace-summary.md found in ${TRACE_DIR}"
  exit 1
fi

echo "Judging scenario: ${SCENARIO_ID}"
echo "Trace: ${TRACE_DIR}"

# Read scenario and trace content
SCENARIO_CONTENT="$(cat "${SCENARIO_FILE}")"
TRACE_CONTENT="$(cat "${TRACE_DIR}/trace-summary.md")"

# Extract criteria section from scenario
CRITERIA="$(sed -n '/^## Satisfaction Criteria/,/^## /p' "${SCENARIO_FILE}" | head -n -1)"
ANTIPATTERNS="$(sed -n '/^## Anti-Patterns/,/^## /p' "${SCENARIO_FILE}")"

# If anti-patterns section goes to end of file, grab it all
if [ -z "${ANTIPATTERNS}" ]; then
  ANTIPATTERNS="$(sed -n '/^## Anti-Patterns/,$p' "${SCENARIO_FILE}")"
fi

# Prepare output
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
JUDGMENT_DIR="${SCRIPT_DIR}/judgments/${TIMESTAMP}"
mkdir -p "${JUDGMENT_DIR}"

JUDGE_INPUT="# Scenario Under Test

${SCENARIO_CONTENT}

# Evidence Report (Trace Summary)

${TRACE_CONTENT}

# Your Task

Evaluate the trace evidence against each satisfaction criterion listed in the scenario. Check for any anti-patterns. Return your judgment as JSON matching the required schema.

The scenario_id is: ${SCENARIO_ID}"

echo "Running judge..."

claude -p "${JUDGE_INPUT}" \
  --output-format json \
  --system-prompt-file "${SCRIPT_DIR}/judge-prompt.md" \
  --json-schema "$(cat "${SCRIPT_DIR}/judgment-schema.json")" \
  --allowedTools "" \
  > "${JUDGMENT_DIR}/${SCENARIO_ID}.json"

echo "Judgment saved to ${JUDGMENT_DIR}/${SCENARIO_ID}.json"

# Print summary
VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['verdict'])" "${JUDGMENT_DIR}/${SCENARIO_ID}.json" 2>/dev/null || echo "unknown")
SCORE=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['satisfaction_score'])" "${JUDGMENT_DIR}/${SCENARIO_ID}.json" 2>/dev/null || echo "?")

echo ""
echo "Result: ${VERDICT} (score: ${SCORE})"
