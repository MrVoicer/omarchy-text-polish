#!/usr/bin/env python3
"""Native messaging host for the Polish browser extension.

Reads one message {text, style, mode, url, editable}, writes the text to a
private temp file and launches the `polish` popup detached, then replies
{"ok": true}. It also records which window is active right now (the browser
that sent the request), so Replace can't paste into an app you switched to
while the popup was loading. The launcher deletes the temp file, including when
it declines to open (a popup is already open, or the text is too long).
"""
import json, os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
STYLES = {"proofread", "casual", "punchy", "concise", "detailed", "formal", "witty", "tweet",
          "summarize", "keypoints", "explain", "translate"}


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
    # Pass long text through: the launcher refuses it with a clear message
    # instead of rewriting a silently truncated part.
    text = str(msg.get("text", ""))[:300_000]
    style = msg.get("style") if msg.get("style") in STYLES else "auto"   # auto: apps.conf decides
    mode = msg.get("mode") if msg.get("mode") in ("reply", "read") else "rewrite"
    url = str(msg.get("url", ""))[:2000]
    if not url.startswith(("http://", "https://")):
        url = ""
    editable = "yes" if msg.get("editable") else "no"
    run = run_dir()
    if not run:
        return reply({"ok": False, "error": "no private runtime directory"})
    try:
        win = json.loads(subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True,
                                        text=True, timeout=2).stdout or "{}").get("address", "")
    except Exception:
        win = ""
    fd, path = tempfile.mkstemp(prefix="browser-", suffix=".txt", dir=run)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    try:
        subprocess.Popen(
            [os.path.join(HERE, "polish"), "--file", path, "--style", style, "--editable", editable,
             "--mode", mode, "--url", url, "--window", win, "--from-browser"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as e:
        os.unlink(path)
        return reply({"ok": False, "error": str(e)})
    reply({"ok": True})


def run_dir():
    """Same rule as lib.sh: $XDG_RUNTIME_DIR/text-polish, else ~/.cache/text-polish;
    never a shared /tmp path. None if it isn't ours or is a symlink."""
    base = os.environ.get("XDG_RUNTIME_DIR", "")
    if not (base and os.path.isdir(base) and os.stat(base).st_uid == os.getuid()):
        base = os.path.join(os.path.expanduser("~"), ".cache")
    d = os.path.join(base, "text-polish")
    os.makedirs(d, mode=0o700, exist_ok=True)
    st = os.lstat(d)
    if os.path.islink(d) or st.st_uid != os.getuid():
        return None
    os.chmod(d, 0o700)
    return d


if __name__ == "__main__":
    main()
