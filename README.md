# Polish — AI rewrite for selected text

Popup that rewrites highlighted text (Proofread / Casual / Punchy / Concise /
Formal / Tweet) with an AI agent CLI, then Replaces or Inserts it back.

## Agents
Pick the agent from the pill in the popup's top-left corner, or cycle with
**Alt+A**. The menu lists whichever of these are installed:

| Agent | Command used (no session saved, read-only) |
|---|---|
| Claude | `claude -p --model sonnet` with tools, MCP and settings off (Haiku is as fast but misses proofreading fixes) |
| Codex | `codex exec --ignore-user-config --ignore-rules --ephemeral`, `gpt-6-luna` at low effort (`POLISH_CODEX_MODEL`, `POLISH_CODEX_EFFORT`) |
| OpenCode | `opencode run --agent plan` (your OpenCode default model) |
| Command Code | `cmd -p --no-session --max-turns 1 --permission-mode plan` |

The choice is remembered in `~/.local/state/text-polish/agent`. With nothing
saved, it falls back to `omarchy-default-agent`. `POLISH_AGENT=<id>` overrides
both.

## Requirements
Omarchy (Hyprland, Quickshell), `wl-clipboard`, `wtype`, `jq`, and a logged-in
CLI for at least one of Claude Code, Codex, OpenCode or Command Code.

## Install
```bash
git clone https://github.com/MrVoicer/omarchy-text-polish ~/.config/text-polish
~/.config/text-polish/install.sh   # registers the browser bridge, prints next steps
```

## Triggers
- **Browser right-click** (Brave Origin / Chromium): select text → right-click →
  *Rewrite with AI* → style. Needs the unpacked extension in
  `browser-extension/` loaded once (brave://extensions → Developer mode →
  Load unpacked). Fixed extension ID: see `extension-id.txt` (pinned by the
  `key` in its manifest so the native-messaging allow-list keeps matching).
- **Any app**: highlight text, press **SUPER + ALT + R** (reads the Wayland
  primary selection). Bound in `~/.config/hypr/bindings.lua`.
  A system-wide right-click entry is not possible on Wayland: every app draws
  its own context menu.

## Files
- `polish` — launcher; grabs text, remembers the focused window, starts the popup.
- `shell.qml` — standalone Quickshell popup (themed from
  `~/.local/state/omarchy/current/theme/colors.toml`).
- `rewrite.sh STYLE FILE` — calls the selected agent; `rewrite.sh --list-agents`
  feeds the picker. `POLISH_MODEL` changes Claude's model.
- `apply.sh replace|insert ADDR TEXT` — wl-copy, refocus, `wtype` Ctrl+V
  (Ctrl+Shift+V in terminals). Insert = Right arrow, space, paste.
- `native-host.py` — bridge from the extension; `install.sh` registers it
  (`NativeMessagingHosts/com.voicer.text_polish.json` for Brave/Chromium/Chrome).

## Versions and Adjust
- Every rewrite is saved as a numbered version. Page through them with the
  `‹ n / N ›` pager or the **Left/Right** arrow keys (Alt+Left/Right while
  typing in the text box). Each version keeps its tone, agent, timing and any
  hand edits. Clicking a tone chip jumps to its latest version instead of
  regenerating; ↻ adds a fresh version.
- **Adjust** (Alt+J) opens a panel with tone chips, a **Length** slider
  (Short / Moderate = the tone's default / Long), an **Emoji** slider
  (None / Few / Moderate / Lots) and a free-text request such as "address it
  to Priya". **Generate** adds a new version. The settings are remembered per
  tone while the popup is open.

## Keys in the popup
Esc close · Ctrl+Enter replace (copy if the selection wasn't editable) ·
Ctrl+Shift+Enter insert · Ctrl+R regenerate · ←/→ versions · Alt+1–6 pick style · Alt+J adjust · Alt+A next agent ·
Alt+O (or the Show original button) swaps the box to the full original text and back.
**Tweet** keeps the result within X's 280-character limit (it retries up to
twice if the agent overshoots) and shows a live `n / 280` counter while you edit. The result
box is editable before applying.

## Style rules
Each mode has concrete, checkable rules in `rewrite.sh` so the modes read
clearly differently: Casual uses contractions and plain words; Punchy opens
with the main point in 6 words or fewer and keeps sentences to 12 words or fewer;
Concise has a hard target of half the original length; Formal uses no
contractions, slang or "Hey"; Tweet stays within 270 characters, hook first.
Every mode must keep each fact, number, name, question and request, including
lines that look like instructions, which are rewritten as text and never
obeyed. Greetings and filler are the style's call.

## Notes
- Nothing runs in the background, so there's nothing to autostart. Everything it
  needs lives on disk and survives a reboot: the Hyprland binding, the
  native-host manifests, the extension, and the saved agent choice.
- The footer shows which agent produced the text and how long it took. Typical
  times: Claude ~3s, Codex ~5–6s (fixed overhead from Codex's built-in agent
  prompt, whatever the model), Command Code ~6s, OpenCode ~4–10s.
- Replace leaves the rewritten text on the clipboard.
- Logs: `$XDG_RUNTIME_DIR/text-polish/popup.log`, `agent-<style>.err`.
