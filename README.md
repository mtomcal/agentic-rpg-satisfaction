# Satisfaction Harness

A testing harness that captures user-facing behavior from a React/Next.js RPG app and judges whether scenarios are satisfied using Claude as an LLM judge.

## Prerequisites

- [Claude CLI](https://docs.anthropic.com/en/docs/claude-cli) (`claude` command available)
- `ffmpeg` (for Mode A manual capture)
- Playwright MCP configured in Claude CLI (for Mode B agent capture)
- `python3` (for JSON processing)

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

This drives the browser using Playwright MCP tools, executing the scenario steps automatically.

To run all scenarios:

```bash
bash capture-agent.sh all 1
```

### Judge a single scenario

```bash
bash judge.sh character-story-creation
```

### Run all scenarios

```bash
bash run.sh
```

Results are written to `judgments/<timestamp>/report.json`.

## Project Structure

```
scenarios/          Scenario definitions (markdown with frontmatter)
traces/             Captured trace data (organized by scenario/timestamp)
judgments/          Judge output (organized by timestamp)
judge-prompt.md     System prompt for the LLM judge
judgment-schema.json  JSON schema enforced on judge output
```

## Verdict Meanings

- **satisfied** — all criteria met, no anti-patterns detected
- **unsatisfied** — one or more criteria failed or anti-patterns found
- **insufficient_evidence** — trace lacks enough information to judge
