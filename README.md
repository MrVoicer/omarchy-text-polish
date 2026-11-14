# Polish — AI rewrite for selected text

Popup that rewrites highlighted text (Proofread / Tweet / Casual / Punchy /
Concise / Detailed / Formal / Witty) with an AI agent CLI, then Replaces or Inserts it back.

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
  `‹ n / N ›` pager or the **Left/Right** arrow keys. While the cursor is in the
  text box, arrows move the cursor; Alt+Left/Right still pages, and clicking
  anywhere outside the text hands the arrows back to paging. Each version keeps its tone, agent, timing and any
  hand edits. Clicking a tone chip jumps to its latest version instead of
  regenerating; ↻ adds a fresh version.
- **Your edits feed the next rewrite.** If you edit the version on screen, ↻,
  Adjust → Generate and new tones rewrite your edited text (the footer says
  "from your edit"). **Shift+click ↻** (or Ctrl+Shift+R) rewrites the original
  selection instead.
- **Adjust** (Alt+J) opens a panel with tone chips, a **Length** slider
  (Short / Moderate = the tone's default / Long), an **Emoji** slider
  (None / Few / Moderate / Lots) and a free-text request such as "address it
  to Priya". **Generate** adds a new version. The settings are remembered per
  tone while the popup is open.

## Layout
Tone chips sit in one row that scrolls sideways (mouse wheel or drag), with
Adjust pinned on the left. The footer is one line; hover its ⓘ icon for the
keyboard shortcuts.

## Keys in the popup
Esc close · Ctrl+Enter replace (copy if the selection wasn't editable) ·
Ctrl+Shift+Enter insert · Ctrl+R regenerate · ←/→ versions · Alt+1–8 pick style · Alt+J adjust · Alt+A next agent ·
Alt+O (or the Show original button) swaps the box to the full original text and back.
**Tweet** keeps the result within X's 280-character limit (it retries up to
twice if the agent overshoots) and shows a live `n / 280` counter while you edit. The result
box is editable before applying.

## Style rules
Each mode has concrete, checkable rules in `rewrite.sh` so the modes read
clearly differently: Casual uses contractions and plain words; Punchy opens
with the main point in 6 words or fewer and keeps sentences to 12 words or fewer;
Concise has a hard target of half the original length; Detailed is 1.5–2×
with context but no invented facts; Formal uses no contractions, slang or
"Hey"; Witty adds one or two kind jokes and allows emoji; Tweet stays within 270 characters, hook first.
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
