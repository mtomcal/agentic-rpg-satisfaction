#!/usr/bin/env bash
# Mode B: Agent capture — use Claude with Playwright MCP to drive the browser
set -euo pipefail

SCENARIO_ID="${1:?Usage: capture-agent.sh <scenario-id|all> [run-count]}"
RUN_COUNT="${2:-1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"

echo ""
echo "========================================"
echo "  CAPTURE MODE B — Agent (Playwright)"
echo "  $(date)"
echo "========================================"

# Collect steps files to process
if [ "${SCENARIO_ID}" = "all" ]; then
  STEPS_FILES=("${SCENARIOS_DIR}"/*.steps.md)
  SCENARIO_COUNT=${#STEPS_FILES[@]}
  echo ""
  echo "  Mode:      all scenarios (${SCENARIO_COUNT} found)"
  echo "  Runs each: ${RUN_COUNT}"
else
  STEPS_FILE="${SCENARIOS_DIR}/${SCENARIO_ID}.steps.md"
  if [ ! -f "${STEPS_FILE}" ]; then
    echo ""
    echo "  ERROR: Scenario not found: ${STEPS_FILE}"
    echo "  Available scenarios:"
    for f in "${SCENARIOS_DIR}"/*.steps.md; do
      echo "    - $(basename "$f" .steps.md)"
    done
    exit 1
  fi
  STEPS_FILES=("${STEPS_FILE}")
  echo ""
  echo "  Scenario:  ${SCENARIO_ID}"
  echo "  Runs:      ${RUN_COUNT}"
fi
echo ""

TOTAL_RUNS=0
SUCCESSFUL_RUNS=0

for STEPS_FILE in "${STEPS_FILES[@]}"; do
  CURRENT_ID="$(basename "${STEPS_FILE}" .steps.md)"
  STEPS_CONTENT="$(cat "${STEPS_FILE}")"

  for RUN in $(seq 1 "${RUN_COUNT}"); do
    TOTAL_RUNS=$((TOTAL_RUNS + 1))
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    TRACE_DIR="${SCRIPT_DIR}/traces/${CURRENT_ID}/${TIMESTAMP}"
    mkdir -p "${TRACE_DIR}"

    echo "----------------------------------------"
    echo "  Scenario: ${CURRENT_ID}"
    echo "  Run:      ${RUN}/${RUN_COUNT}"
    echo "  Output:   ${TRACE_DIR}"
    echo "----------------------------------------"
    echo ""
    echo "  [1/2] Launching Playwright agent..."
    echo "         Driving browser at http://localhost:3000"
    echo "         This may take a few minutes..."

    CAPTURE_PROMPT="You are a QA tester using a web browser via Playwright MCP tools. Your job is to execute the following test steps and document everything you observe.

## Steps
${STEPS_CONTENT}

## Instructions
1. Follow the steps described above exactly
2. After each step, take a screenshot and describe what you see
3. Note any errors, unexpected behavior, or deviations from expected results
4. If a step fails, still attempt remaining steps and document the failure
5. At the end, write a complete trace summary

## Output
Write your complete trace (all observations, screenshots taken, and summary) as a detailed markdown report. Describe what you literally see on screen — do not judge whether criteria are met, just report factual observations."

    # Run from /tmp to prevent Claude from reading CLAUDE.md or repo files (anti-contamination)
    # Stream assistant output to terminal via stream-filter, save final result for trace extraction
    if (cd /tmp && claude -p "${CAPTURE_PROMPT}" \
      --output-format stream-json --verbose \
      --allowedTools "mcp__playwright__*") \
      2>"${TRACE_DIR}/capture-stderr.log" \
      | python3 "${SCRIPT_DIR}/stream-filter.py" "${TRACE_DIR}/trace-raw.json"; then
      # Extract text result from the stream envelope
      python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
result = data.get('result', '')
# structured_output takes priority if present
so = data.get('structured_output')
if isinstance(so, str):
    result = so
print(result)
" "${TRACE_DIR}/trace-raw.json" > "${TRACE_DIR}/trace-summary.md"

      TRACE_SIZE=$(wc -c < "${TRACE_DIR}/trace-summary.md")
      TRACE_LINES=$(wc -l < "${TRACE_DIR}/trace-summary.md")
      SUCCESSFUL_RUNS=$((SUCCESSFUL_RUNS + 1))

      echo "  [2/2] Trace captured successfully"
      echo "         ${TRACE_SIZE} bytes, ${TRACE_LINES} lines"
    else
      echo "  [2/2] ERROR: Capture failed (exit code $?)"
      echo "         Check ${TRACE_DIR}/capture-stderr.log for details"
    fi
    echo ""
  done
done

echo "========================================"
echo "  CAPTURE COMPLETE"
echo "========================================"
echo ""
echo "  Runs: ${SUCCESSFUL_RUNS}/${TOTAL_RUNS} successful"
echo ""
if [ "${SUCCESSFUL_RUNS}" -gt 0 ]; then
  echo "  Next step: bash run.sh"
fi
echo ""
