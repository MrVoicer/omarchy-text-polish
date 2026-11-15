#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Turn `claude -p --output-format stream-json --include-partial-messages` into
Polish's line protocol: one `P <json string>` line per text delta on stdout.

The final text (the result event, else the joined deltas) is written to the
file named by argv[1]; errors go to stderr. Used by rewrite.sh when the popup
asks for streaming (POLISH_STREAM=1).
"""
import json
import sys


def main():
    outf = sys.argv[1]
    parts, final = [], None
    for line in sys.stdin:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        kind = ev.get("type")
        if kind == "stream_event":
            e = ev.get("event") or {}
            d = e.get("delta") or {}
            if e.get("type") == "content_block_delta" and d.get("type") == "text_delta":
                chunk = d.get("text") or ""
                parts.append(chunk)
                sys.stdout.write("P " + json.dumps(chunk) + "\n")
                sys.stdout.flush()
        elif kind == "result":
            if not ev.get("is_error") and isinstance(ev.get("result"), str):
                final = ev["result"]
            else:
                sys.stderr.write(str(ev.get("result") or ev.get("subtype") or "error") + "\n")
    with open(outf, "w") as f:
        f.write(final if final is not None else "".join(parts))


if __name__ == "__main__":
    main()
