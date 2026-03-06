# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A satisfaction testing harness that validates a React/Next.js RPG app by capturing user-facing behavior and judging it with an LLM. This is a **harness repo** — it tests a separate app (assumed at `http://localhost:3000`), not itself.

The full spec lives at `specs/satisfaction-harness-spec.md`.

## Key Commands

```bash
# Capture traces
bash capture-manual.sh <recording.mp4> <scenario-id>   # Mode A: from screen recording
bash capture-agent.sh <scenario-id|all> [run-count]     # Mode B: automated via Playwright MCP

# Judge
bash judge.sh <scenario-id> [trace-dir]                 # Single scenario
bash run.sh                                              # All scenarios, produces report.json
```

## Architecture

The pipeline is: **Capture → Trace → Judge → Report**.

1. **Scenarios** (`scenarios/*.md`) — Markdown with YAML frontmatter (`id`, `category`, `priority`, `timeout`, `setup`). Each has Steps, Satisfaction Criteria (keyed by ID like `character_created`), and Anti-Patterns.

2. **Capture** produces `traces/<scenario-id>/<timestamp>/trace-summary.md`:
   - `capture-manual.sh`: ffmpeg extracts frames → samples up to 20 → `claude -p` with vision describes them
   - `capture-agent.sh`: `claude -p` with `--allowedTools "mcp__playwright__*"` drives the browser

3. **Judge** (`judge.sh` / `run.sh`) calls `claude -p` with:
   - `--system-prompt-file judge-prompt.md` (skeptical QA judge persona)
   - `--json-schema` from `judgment-schema.json` (enforced output structure)
   - `--allowedTools ""` (no tools — pure reasoning)
   - Output goes to `judgments/<timestamp>/<scenario-id>.json`

4. **Report** (`run.sh` only): tallies verdicts, flags critical failures (scenarios with `priority: critical`), writes `judgments/<timestamp>/report.json`, exits non-zero on critical failures.

## Judgment Schema

Verdicts: `satisfied`, `unsatisfied`, `insufficient_evidence`. Score is 0–1. Each criterion result has `met` (bool or null) and `evidence` (specific citation). Anti-patterns auto-fail related criteria.

## Adding a New Scenario

Create `scenarios/<id>.md` with the same structure as `character-story-creation.md`: frontmatter, Description, Steps, Satisfaction Criteria, Anti-Patterns. The `id` in frontmatter must match the filename.

## Dependencies

All scripts use `claude` CLI (Claude Code), `python3` (JSON processing), and `bash`. `capture-manual.sh` also needs `ffmpeg`. `capture-agent.sh` needs Playwright MCP configured.
