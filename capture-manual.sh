#!/usr/bin/env bash
# Mode A: Manual capture — extract frames from a screen recording and generate a trace summary
set -euo pipefail

RECORDING="${1:?Usage: capture-manual.sh <recording-file> <scenario-id>}"
SCENARIO_ID="${2:?Usage: capture-manual.sh <recording-file> <scenario-id>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TRACE_DIR="${SCRIPT_DIR}/traces/${SCENARIO_ID}/${TIMESTAMP}"

echo ""
echo "========================================"
echo "  CAPTURE MODE A — Manual (Recording)"
echo "  $(date)"
echo "========================================"
echo ""
echo "  Scenario:  ${SCENARIO_ID}"
echo "  Recording: ${RECORDING}"
echo "  Output:    ${TRACE_DIR}"
echo ""

# --- Step 1: Extract frames ---
echo "[1/4] Extracting frames from recording..."
mkdir -p "${TRACE_DIR}/frames"
ffmpeg -i "${RECORDING}" -vf "fps=1" -q:v 2 "${TRACE_DIR}/frames/frame_%04d.jpg" 2>/dev/null

FRAME_COUNT=$(ls "${TRACE_DIR}/frames"/*.jpg 2>/dev/null | wc -l)
echo "       Extracted ${FRAME_COUNT} frames (1 per second)"

if [ "${FRAME_COUNT}" -eq 0 ]; then
  echo ""
  echo "  ERROR: No frames extracted. Is the recording file valid?"
  echo "         File: ${RECORDING}"
  exit 1
fi

# --- Step 2: Sample frames ---
echo "[2/4] Sampling frames (max 20 evenly spaced)..."
SAMPLED_DIR="${TRACE_DIR}/sampled"
mkdir -p "${SAMPLED_DIR}"

if [ "${FRAME_COUNT}" -le 20 ]; then
  cp "${TRACE_DIR}/frames"/*.jpg "${SAMPLED_DIR}/"
else
  STEP=$(( FRAME_COUNT / 20 ))
  IDX=1
  for f in "${TRACE_DIR}/frames"/*.jpg; do
    if (( IDX % STEP == 0 )); then
      cp "$f" "${SAMPLED_DIR}/"
    fi
    IDX=$((IDX + 1))
  done
fi

SAMPLED_COUNT=$(ls "${SAMPLED_DIR}"/*.jpg 2>/dev/null | wc -l)
echo "       Selected ${SAMPLED_COUNT} frames for analysis"

# --- Step 3: Build frame arguments ---
echo "[3/4] Preparing vision prompt..."
FRAME_ARGS=""
for f in "${SAMPLED_DIR}"/*.jpg; do
  FRAME_ARGS="${FRAME_ARGS} ${f}"
done

# --- Step 4: Generate trace via Claude vision ---
echo "[4/4] Sending frames to Claude for analysis..."
echo "       This may take a minute..."

# Run from /tmp to prevent Claude from reading CLAUDE.md or repo files (anti-contamination)
(cd /tmp && claude -p "You are analyzing a screen recording of a web application interaction for scenario '${SCENARIO_ID}'.

These are sampled frames from the recording, in chronological order. For each frame, describe:
1. What is visible on screen (UI elements, text content, layout)
2. What action the user appears to have taken since the last frame
3. Any errors, loading states, or unexpected behavior

After describing individual frames, provide a summary of the complete user flow observed.

Focus on factual observations — what is literally visible — not interpretations." \
  ${FRAME_ARGS}) \
  > "${TRACE_DIR}/trace-summary.md"

TRACE_SIZE=$(wc -c < "${TRACE_DIR}/trace-summary.md")
TRACE_LINES=$(wc -l < "${TRACE_DIR}/trace-summary.md")

echo ""
echo "========================================"
echo "  CAPTURE COMPLETE"
echo "========================================"
echo ""
echo "  Trace: ${TRACE_DIR}/trace-summary.md"
echo "  Size:  ${TRACE_SIZE} bytes, ${TRACE_LINES} lines"
echo ""
echo "  Next step: bash judge.sh ${SCENARIO_ID}"
echo ""
