# Satisfaction Harness

A testing harness that captures user-facing behavior from a React/Next.js RPG app and judges whether scenarios are satisfied using Claude as an LLM judge.

## Prerequisites

- [Claude CLI](https://docs.anthropic.com/en/docs/claude-cli) (`claude` command available)
- `ffmpeg` (for Mode A manual capture)
- Playwright MCP configured in Claude CLI (for Mode B agent capture)
- `python3` with `jsonschema` package

## Quick Start

### Mode A: Manual Capture (screen recording)

Record yourself performing the scenario in the app, then:

```bash
bash capture-manual.sh path/to/recording.mp4 character-story-creation
```

This extracts frames, samples them, and generates a trace summary via Claude vision.

### Mode B: Agent Capture (automated via Playwright)

With the app running at `http://localhost:3000`:

```bash
bash capture-agent.sh character-story-creation 1
```

This drives the browser using Playwright MCP tools, executing the scenario steps automatically. The capture agent sees only the steps file — never the judgment criteria — so its trace is pure observation without pass/fail commentary.

To run all scenarios:

```bash
bash capture-agent.sh all 3
```

### Judge a single scenario

```bash
bash judge.sh character-story-creation
```

### Run all scenarios (judge + report)

```bash
bash run.sh
```

Results are written to `judgments/<timestamp>/report.json`. Failed criteria are written to `judgments/<timestamp>/failures.jsonl` for handoff to coding agents.

### Makefile shortcuts

```bash
make help              # Show all targets
make capture SCENARIO=x
make capture-all RUNS=3
make judge SCENARIO=x
make run               # Full pipeline: judge all + report
make clean             # Delete all traces and judgments
```

## Project Structure

```
scenarios/
  <id>.steps.md        Steps for capture agent (observe only, no criteria)
  <id>.criteria.md     Satisfaction criteria + anti-patterns (judge only)
traces/                Captured trace data (organized by scenario/timestamp)
judgments/             Judge output (organized by timestamp)
judge-prompt.md        System prompt for the LLM judge
judgment-schema.json   JSON schema enforced on judge output
stream-filter.py       Real-time streaming display for claude output
extract-judgment.py    JSON extraction + schema validation
```

## Scenario Isolation

Each scenario is split into two files to prevent the capture agent from biasing the judge:

- **`<id>.steps.md`** — What to do and observe. The capture agent sees only this. No criteria, no anti-patterns.
- **`<id>.criteria.md`** — How to judge. The judge sees only this plus the trace evidence. No steps.

The capture agent describes what it sees without knowing what "good" looks like. The judge evaluates uncontaminated evidence against criteria it receives separately.

## Verdict Meanings

- **satisfied** — all criteria met, no anti-patterns detected
- **unsatisfied** — one or more criteria failed or anti-patterns found
- **insufficient_evidence** — trace lacks enough information to judge

## Full Spec

See `specs/satisfaction-harness-spec.md` for the complete architecture and design rationale.
