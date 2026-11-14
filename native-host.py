#!/usr/bin/env python3
"""Native messaging host for the Polish browser extension.

Reads one message {text, style, editable}, writes the text to a private temp
file and launches the `polish` popup detached, then replies {"ok": true}.
"""
import json, os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
STYLES = {"proofread", "casual", "punchy", "concise", "detailed", "formal", "witty", "tweet",
          "summarize", "keypoints", "explain"}


def reply(obj):
    data = json.dumps(obj).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()


def main():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        return
    (size,) = struct.unpack("=I", raw)
    if size > 1_000_000:
        return reply({"ok": False, "error": "message too large"})
    msg = json.loads(sys.stdin.buffer.read(size))
    text = str(msg.get("text", ""))[:20000]
    style = msg.get("style") if msg.get("style") in STYLES else "auto"   # auto: apps.conf decides
    mode = msg.get("mode") if msg.get("mode") in ("reply", "read") else "rewrite"
    url = str(msg.get("url", ""))[:2000]
    if not url.startswith(("http://", "https://")):
        url = ""
    editable = "yes" if msg.get("editable") else "no"
    run = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "text-polish")
    os.makedirs(run, mode=0o700, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix="browser-", suffix=".txt", dir=run)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    subprocess.Popen(
        [os.path.join(HERE, "polish"), "--file", path, "--style", style, "--editable", editable,
         "--mode", mode, "--url", url],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    reply({"ok": True})


if __name__ == "__main__":
    main()
