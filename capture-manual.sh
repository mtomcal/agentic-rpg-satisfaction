#!/usr/bin/env bash
# Mode A: Manual capture — extract frames from a screen recording and generate a trace summary
set -euo pipefail

RECORDING="${1:?Usage: capture-manual.sh <recording-file> <scenario-id>}"
SCENARIO_ID="${2:?Usage: capture-manual.sh <recording-file> <scenario-id>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TRACE_DIR="${SCRIPT_DIR}/traces/${SCENARIO_ID}/${TIMESTAMP}"

mkdir -p "${TRACE_DIR}/frames"

echo "Extracting frames from ${RECORDING}..."
# Extract one frame per second
ffmpeg -i "${RECORDING}" -vf "fps=1" -q:v 2 "${TRACE_DIR}/frames/frame_%04d.jpg" 2>/dev/null

FRAME_COUNT=$(ls "${TRACE_DIR}/frames"/*.jpg 2>/dev/null | wc -l)
echo "Extracted ${FRAME_COUNT} frames"

if [ "${FRAME_COUNT}" -eq 0 ]; then
  echo "Error: No frames extracted from recording"
  exit 1
fi

# Sample frames evenly — take up to 20 frames spread across the recording
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
echo "Sampled ${SAMPLED_COUNT} frames for analysis"

# Build the vision prompt with sampled frames
FRAME_ARGS=""
for f in "${SAMPLED_DIR}"/*.jpg; do
  FRAME_ARGS="${FRAME_ARGS} ${f}"
done

echo "Generating trace summary via claude..."

# Use claude CLI with vision to describe the sampled frames
claude -p "You are analyzing a screen recording of a web application interaction for scenario '${SCENARIO_ID}'.

These are sampled frames from the recording, in chronological order. For each frame, describe:
1. What is visible on screen (UI elements, text content, layout)
2. What action the user appears to have taken since the last frame
3. Any errors, loading states, or unexpected behavior

After describing individual frames, provide a summary of the complete user flow observed.

Focus on factual observations — what is literally visible — not interpretations." \
  ${FRAME_ARGS} \
  > "${TRACE_DIR}/trace-summary.md"

echo "Trace saved to ${TRACE_DIR}/trace-summary.md"
echo "Done."
