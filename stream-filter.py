#!/usr/bin/env python3
"""Filter claude CLI stream-json output: print assistant text to stderr, write final JSON to file.

Reads newline-delimited JSON from stdin (claude --output-format stream-json).
Prints assistant text content to stderr in real-time for human readability.
Writes the final result JSON object to the specified output file.

Usage: claude -p ... --output-format stream-json | python3 stream-filter.py <output-file>
"""
import json
import sys

DIM = "\033[2m"
RESET = "\033[0m"
CYAN = "\033[36m"


def log(msg):
    sys.stderr.write(msg)
    sys.stderr.flush()


def main():
    if len(sys.argv) < 2:
        print("Usage: stream-filter.py <output-file>", file=sys.stderr)
        sys.exit(1)

    output_path = sys.argv[1]
    last_result = None

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        event_type = event.get("type", "")

        if event_type == "assistant":
            message = event.get("message", {})
            content = message.get("content", [])
            for block in content:
                if isinstance(block, dict):
                    if block.get("type") == "text":
                        text = block.get("text", "")
                        if text:
                            log(f"{DIM}{text}{RESET}")
                    elif block.get("type") == "tool_use":
                        name = block.get("name", "")
                        tool_input = block.get("input", {})
                        # Show tool calls concisely
                        if "url" in tool_input:
                            log(f"\n{CYAN}  → {name}: {tool_input['url']}{RESET}\n")
                        elif "selector" in tool_input:
                            log(f"\n{CYAN}  → {name}: {tool_input['selector']}{RESET}\n")
                        else:
                            log(f"\n{CYAN}  → {name}{RESET}\n")
                elif isinstance(block, str):
                    log(f"{DIM}{block}{RESET}")

        elif event_type == "result":
            last_result = event
            log("\n")

    if last_result is not None:
        with open(output_path, "w") as f:
            json.dump(last_result, f, indent=2)
    else:
        print("ERROR: No result event received from stream", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
