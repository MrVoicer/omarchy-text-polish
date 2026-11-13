# Polish — AI rewrite for selected text

Popup that rewrites highlighted text (Proofread / Casual / Punchy / Concise /
Formal / Tweet) with Omarchy's default agent (`omarchy-default-agent`, currently
`claude`; `codex` also supported), then Replaces or Inserts it back.

## Requirements
Omarchy (Hyprland, Quickshell), `wl-clipboard`, `wtype`, `jq`, and a logged-in
`claude` (or `codex`) CLI.

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
- `rewrite.sh STYLE FILE` — calls the agent (claude: `-p --model haiku`, no
  tools/MCP/settings). Override with `POLISH_AGENT`, `POLISH_MODEL`.
- `apply.sh replace|insert ADDR TEXT` — wl-copy, refocus, `wtype` Ctrl+V
  (Ctrl+Shift+V in terminals). Insert = Right arrow, space, paste.
- `native-host.py` — bridge from the extension; `install.sh` registers it
  (`NativeMessagingHosts/com.voicer.text_polish.json` for Brave/Chromium/Chrome).

## Keys in the popup
Esc close · Ctrl+Enter replace (copy if the selection wasn't editable) ·
Ctrl+Shift+Enter insert · Ctrl+R regenerate · Alt+1–6 pick style.
**Tweet** keeps the result within X's 280-character limit (it retries up to
twice if the agent overshoots) and shows a live `n / 280` counter while you edit. The result
box is editable before applying.

## Notes
- Replace leaves the rewritten text on the clipboard.
- Logs: `$XDG_RUNTIME_DIR/text-polish/popup.log`, `agent-<style>.err`.
