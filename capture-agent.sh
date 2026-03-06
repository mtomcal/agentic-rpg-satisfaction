#!/usr/bin/env bash
# Mode B: Agent capture — use Claude with Playwright MCP to drive the browser
set -euo pipefail

SCENARIO_ID="${1:?Usage: capture-agent.sh <scenario-id|all> [run-count]}"
RUN_COUNT="${2:-1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"

# Collect scenario files to process
if [ "${SCENARIO_ID}" = "all" ]; then
  SCENARIO_FILES=("${SCENARIOS_DIR}"/*.md)
else
  SCENARIO_FILE="${SCENARIOS_DIR}/${SCENARIO_ID}.md"
  if [ ! -f "${SCENARIO_FILE}" ]; then
    echo "Error: Scenario file not found: ${SCENARIO_FILE}"
    exit 1
  fi
  SCENARIO_FILES=("${SCENARIO_FILE}")
fi

for SCENARIO_FILE in "${SCENARIO_FILES[@]}"; do
  CURRENT_ID="$(basename "${SCENARIO_FILE}" .md)"
  SCENARIO_CONTENT="$(cat "${SCENARIO_FILE}")"

  for RUN in $(seq 1 "${RUN_COUNT}"); do
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    TRACE_DIR="${SCRIPT_DIR}/traces/${CURRENT_ID}/${TIMESTAMP}"
    mkdir -p "${TRACE_DIR}"

    echo "=== Run ${RUN}/${RUN_COUNT} for scenario: ${CURRENT_ID} ==="

    CAPTURE_PROMPT="You are a QA tester using a web browser via Playwright MCP tools. Your job is to execute the following test scenario and document everything you observe.

## Scenario
${SCENARIO_CONTENT}

## Instructions
1. Follow the steps described in the scenario exactly
2. After each step, take a screenshot and describe what you see
3. Note any errors, unexpected behavior, or deviations from expected results
4. If a step fails, still attempt remaining steps and document the failure
5. At the end, write a complete trace summary

## Output
Write your complete trace (all observations, screenshots taken, and summary) as a detailed markdown report. Be factual — describe what you literally see on screen."

    echo "Driving browser with Playwright MCP..."

    claude -p "${CAPTURE_PROMPT}" \
      --allowedTools "mcp__playwright__*" \
      > "${TRACE_DIR}/trace-summary.md"

    echo "Trace saved to ${TRACE_DIR}/trace-summary.md"
  done
done

echo "All capture runs complete."
