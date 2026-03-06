#!/usr/bin/env python3
"""Extract clean judgment JSON from claude CLI output.

The claude CLI with --output-format json wraps results in an envelope:
  {"type":"result", "result": "...text with ```json {...}```...", ...}

This script extracts the inner JSON object, normalizes it to match the
judgment schema (criteria_results as array, anti_patterns_detected as array
of strings), and writes clean JSON.
"""
import json
import os
import re
import sys

import jsonschema


def normalize_judgment(data):
    """Normalize judgment data to match the expected schema."""
    # Convert criteria object to criteria_results array
    if "criteria" in data and "criteria_results" not in data:
        criteria = data.pop("criteria")
        if isinstance(criteria, dict):
            data["criteria_results"] = [
                {"criterion": k, "met": v.get("met"), "evidence": v.get("evidence", "")}
                for k, v in criteria.items()
            ]
        elif isinstance(criteria, list):
            data["criteria_results"] = criteria

    # Ensure criteria_results exists
    if "criteria_results" not in data:
        data["criteria_results"] = []

    # Normalize anti_patterns_detected to array of strings
    if "anti_patterns_detected" in data:
        normalized = []
        for item in data["anti_patterns_detected"]:
            if isinstance(item, str):
                normalized.append(item)
            elif isinstance(item, dict):
                # {"pattern": "...", "details": "..."} -> "pattern: details"
                pattern = item.get("pattern", item.get("name", ""))
                details = item.get("details", item.get("description", ""))
                normalized.append(f"{pattern}: {details}" if details else pattern)
        data["anti_patterns_detected"] = normalized
    else:
        data["anti_patterns_detected"] = []

    # Ensure required fields
    data.setdefault("notes", "")
    data.setdefault("satisfaction_score", 0)
    data.setdefault("verdict", "insufficient_evidence")
    data.setdefault("scenario_id", "unknown")

    return data


def extract_judgment(raw_path, out_path):
    with open(raw_path) as f:
        raw = f.read()

    data = None

    # Try parsing as direct JSON first (ideal case — clean JSON with no envelope)
    try:
        parsed = json.loads(raw)
        if "scenario_id" in parsed and "verdict" in parsed:
            data = parsed
    except (json.JSONDecodeError, TypeError):
        parsed = None

    # Try claude CLI envelope
    if data is None:
        try:
            if parsed is None:
                parsed = json.loads(raw)

            # Preferred: structured_output field (when --json-schema works correctly)
            if isinstance(parsed.get("structured_output"), dict):
                data = parsed["structured_output"]

            # Fallback: result field contains prose or JSON
            if data is None:
                text = parsed.get("result", "")
        except (json.JSONDecodeError, TypeError):
            text = raw

        # Extract JSON from markdown code block
        match = re.search(r'```json\s*(\{.*?\})\s*```', text, re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(1))
            except json.JSONDecodeError:
                pass

        # Try finding a raw JSON object with nested braces
        if data is None:
            # Find the largest JSON object containing scenario_id
            for match in re.finditer(r'\{', text):
                start = match.start()
                depth = 0
                end = start
                for i in range(start, len(text)):
                    if text[i] == '{':
                        depth += 1
                    elif text[i] == '}':
                        depth -= 1
                        if depth == 0:
                            end = i + 1
                            break
                candidate = text[start:end]
                if '"scenario_id"' in candidate and '"verdict"' in candidate:
                    try:
                        data = json.loads(candidate)
                        break
                    except json.JSONDecodeError:
                        continue

    if data is None:
        print(f"ERROR: Could not extract judgment JSON from {raw_path}", file=sys.stderr)
        sys.exit(1)

    data = normalize_judgment(data)

    # Validate against judgment schema
    script_dir = os.path.dirname(os.path.abspath(__file__))
    schema_path = os.path.join(script_dir, "judgment-schema.json")
    with open(schema_path) as f:
        schema = json.load(f)

    try:
        jsonschema.validate(instance=data, schema=schema)
    except jsonschema.ValidationError as e:
        print(f"VALIDATION ERROR: {e.message}", file=sys.stderr)
        print(f"  Path: {' > '.join(str(p) for p in e.absolute_path)}", file=sys.stderr)
        print(f"  Schema rule: {e.schema_path}", file=sys.stderr)
        # Write the invalid data for debugging
        with open(out_path + ".invalid.json", "w") as f:
            json.dump(data, f, indent=2)
        print(f"  Invalid output saved to: {out_path}.invalid.json", file=sys.stderr)
        sys.exit(1)

    with open(out_path, "w") as f:
        json.dump(data, f, indent=2)

    return data


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: extract-judgment.py <raw-output> <clean-output>", file=sys.stderr)
        sys.exit(1)
    data = extract_judgment(sys.argv[1], sys.argv[2])
    print(json.dumps({"verdict": data["verdict"], "score": data.get("satisfaction_score", "?")}, indent=2))
