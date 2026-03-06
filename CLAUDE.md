# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A satisfaction testing harness that validates a React/Next.js RPG app by capturing user-facing behavior and judging it with an LLM. This is a **harness repo** — it tests a separate app (assumed at `http://localhost:3000`), not itself.

The full spec lives at `specs/satisfaction-harness-spec.md`.

## Key Commands

```bash
make help                # Show all targets

make capture             # Agent capture (default scenario)
make capture SCENARIO=x  # Agent capture (specific scenario)
make capture-all RUNS=3  # All scenarios, 3 runs each
make capture-manual RECORDING=file.mp4 SCENARIO=x  # From screen recording

make judge SCENARIO=x    # Judge single scenario
make run                 # Judge all scenarios, produce report + failures.jsonl

make clean               # Delete all traces and judgments
make clean-traces        # Delete traces only
make clean-judgments      # Delete judgments only
```

## Architecture

The pipeline is: **Capture → Trace → Judge → Validate → Report**.

1. **Scenarios** (`scenarios/*.md`) — Markdown with YAML frontmatter (`id`, `category`, `priority`, `timeout`, `setup`). Each has Steps, Satisfaction Criteria (keyed by ID like `character_created`), and Anti-Patterns.

2. **Capture** produces `traces/<scenario-id>/<timestamp>/trace-summary.md`:
   - `capture-manual.sh`: ffmpeg extracts frames → samples up to 20 → `claude -p` with vision describes them
   - `capture-agent.sh`: `claude -p` with `--allowedTools "mcp__playwright__*"` drives the browser

3. **Judge** (`judge.sh` / `run.sh`) calls `claude -p` with:
   - `--system-prompt-file judge-prompt.md` (skeptical QA judge persona)
   - `--json-schema` from `judgment-schema.json` (enforced output structure)
   - `--allowedTools ""` (no tools — pure reasoning)
   - Output goes to `judgments/<timestamp>/<scenario-id>.json`

4. **Validate** (`extract-judgment.py`): extracts JSON from claude CLI envelope, normalizes schema variants (e.g. `criteria` object → `criteria_results` array), validates against `judgment-schema.json` using `jsonschema`. On validation failure, feeds the error back to Claude for self-correction (up to 2 retries).

5. **Report** (`run.sh` only): tallies verdicts, flags critical failures (scenarios with `priority: critical`), writes `judgments/<timestamp>/report.json` and `failures.jsonl`, exits non-zero on critical failures.

## Anti-Contamination

All `claude -p` calls run from a `(cd /tmp && ...)` subshell to prevent the spawned Claude from reading `CLAUDE.md` or other repo files. This avoids biasing the judge or capture agent with harness-internal knowledge.

## Judgment Schema

Verdicts: `satisfied`, `unsatisfied`, `insufficient_evidence`. Score is 0–1. Each criterion result has `met` (bool or null) and `evidence` (specific citation). Anti-patterns auto-fail related criteria.

## Failures Output

`run.sh` produces `judgments/<timestamp>/failures.jsonl` — one JSON line per failed criterion across all scenarios. Each line includes `scenario_id`, `criterion`, `evidence`, `anti_patterns`, `priority`, `scenario_file`, and `notes`. Designed to be passed directly to coding agents for fixing.

## Adding a New Scenario

Create `scenarios/<id>.md` with the same structure as `character-story-creation.md`: frontmatter, Description, Steps, Satisfaction Criteria, Anti-Patterns. The `id` in frontmatter must match the filename.

## Dependencies

All scripts use `claude` CLI (Claude Code), `python3` (with `jsonschema` package), and `bash`. `capture-manual.sh` also needs `ffmpeg`. `capture-agent.sh` needs Playwright MCP configured.
