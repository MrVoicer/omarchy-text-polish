# Polish — AI rewrite for selected text

Popup that rewrites highlighted text (Proofread / Tweet / Casual / Punchy /
Concise / Detailed / Formal / Witty) with an AI agent CLI, then Replaces or Inserts it back.
Also drafts replies and summarizes/explains text. Full feature list for the
landing page: [FEATURES.md](FEATURES.md).

## Agents
Pick the agent from the pill in the popup's top-left corner, or cycle with
**Alt+A**. The menu lists whichever of these are installed:

| Agent | Command used (no session saved, read-only) |
|---|---|
| Claude | `claude -p --model sonnet` with tools, MCP and settings off (Haiku is as fast but misses proofreading fixes) |
| Codex | `codex exec --ignore-user-config --ignore-rules --ephemeral`, `gpt-6-luna` at low effort (`POLISH_CODEX_MODEL`, `POLISH_CODEX_EFFORT`) |
| OpenCode | `opencode run --agent plan` (your OpenCode default model) |
| Command Code | `commandcode -p --no-session --max-turns 1 --permission-mode plan` |

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
- **Reply straight away**: **Shift + Right Alt** or **SUPER + ALT + Y** opens
  directly in Reply mode.
- **Any app**: highlight text, press **SUPER + ALT + R** or tap **Right Alt** (reads the Wayland
  primary selection). Bound in `~/.config/hypr/bindings.lua`.
- **Apps that don't share their selection**: Ctrl+C, then **SUPER + ALT + C**
  (`polish --clipboard`) works on the clipboard instead. Copy-only in Rewrite
  (the text could have come from anywhere, so nothing is pasted over).
- **Stop**: Esc or the ■ button (the ↻ while generating) ends the run, agent
  and all. Agent failures show one plain sentence with the fix (sign in, usage
  limit, network, model, not installed, timeout), then the raw details.
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

## Reply mode
Switch **Rewrite | Reply** in the header (Alt+M), or right-click a message in
Brave and choose **Reply with AI**. Reply drafts the answer to the selected
message instead of restyling it. Type what you want to say in the box at the top
("yes, but Monday works better") and press Enter. With no intent it writes a
neutral reply that commits to nothing. It's told never to invent times, prices or
promises: missing details become `[placeholders]`, highlighted in the result.
**Tab** / **Shift+Tab** select them one by one (type to fill); Paste or Copy
with any left asks once first (press again to send as is). Every tone applies
(Proofread shows as **Standard**). If you edit a reply and regenerate, your
edit is used as the draft. Buttons: **Paste** at your cursor in the source
window, or **Copy** (copies and closes) to paste into the chat yourself. From
the browser's right-click menu on page text (a tweet, say), selecting it took
the cursor out of the reply box, so only Copy is offered and a toast says to
click the reply box and press Ctrl+V.

## Read mode
For text you're reading rather than writing, the **Read** tab (Alt+M cycles
Rewrite → Reply → Read; Brave's right-click **Read with AI**) has its own chips:
- **Summarize**: the main point in a sentence or two, about a quarter of the
  original's length at most.
- **Points** (key points): 3–7 short bullets, keeping numbers, names, dates and action items.
- **Explain**: what it means in plain words, with jargon and acronyms defined.
- **Translate**: into the language on the `→ English ▾` pill (Alt+L opens the
  list: Indian and world languages, or type any other). Picking one makes a new
  version and is remembered (`translateTo`). Mixed or romanized text (Hinglish,
  Tanglish) is fully translated; text already in the target language goes to
  English. Uses the language's own script; ~3s (no extra thinking).

Adjust works here too (Length plus a request like "just the deadlines"; no
emoji slider). The buttons are **Close** and **Copy**, and Copy keeps the popup
open. `polish --mode read` opens straight into it. Read opens on the action
you used last (saved as `lastRead` in `settings.json`); Brave's Read with AI
submenu picks one explicitly. With Claude, Read thinks
before answering so figures and unit conversions come out right: Explain at
high effort, Summarize and Points at medium (about 4s even on long articles;
high took 10–18s for the same result), Translate without. `POLISH_CLAUDE_EFFORT`
overrides it.

## Tone by app (`apps.conf`)
Without an explicit tone, Polish starts in the tone of the first rule whose
regex matches the window class, title and (from Brave) the page URL. The
shipped rules: X → Tweet, WhatsApp/Telegram/Signal/Discord/Slack → Casual,
Gmail/Outlook/LinkedIn → Formal, anything else → Proofread. Edit
`apps.conf` to add your own. A tone picked in Brave's menu always wins.

## Streaming
With Claude, text appears as it is written (`stream-json` deltas through
`stream_filter.py`). The first words show in about 2s instead of waiting for
the whole result. Other agents return all at once.

## Undo
After Replace, Insert or Paste, Polish's own toast (`toast.qml`, bottom of the
screen; shows even with Do Not Disturb on, takes no keyboard focus) offers
**Undo** for 10 seconds (paused while hovered); **SUPER + ALT + Z**
(`polish --undo`) works for 10 minutes. Each Replace undoes once: a second press
says "Already undone" rather than sending another Ctrl+Z. Attempts are logged to
`$XDG_RUNTIME_DIR/text-polish/undo.log`. It refocuses that
window and sends the app's own undo (Ctrl+Z), so the original comes back
exactly; Insert is a single paste so one undo removes it. Undo right away: if
you've typed more, Ctrl+Z undoes your typing first. Terminals have no undo, so
there it puts your original text on the clipboard instead.

## Safety
- Replace/Insert/Paste paste only into the window the text came from, and only
  after confirming it's focused; if it's gone, nothing is pasted and a toast
  says the text is on the clipboard. Browser requests carry the browser window
  the request came from; if that isn't a browser, the popup is Copy-only.
- Selections over 20,000 characters are refused (instead of rewriting part of
  text that Replace would overwrite whole).
- Runtime files live in `$XDG_RUNTIME_DIR/text-polish` (or `~/.cache/text-polish`),
  never a shared `/tmp` path; settings and history are `600` in a `700` folder.
- One launch at a time (lock + per-launch input file); settings, history and
  undo writes are locked and atomic; each agent run has its own temp files.

## History
The results you use (Replace, Insert, Paste, Copy) and the one on screen when
you close are saved: **Alt+H** or the clock button, or tap **Right Alt with
nothing selected**. Search, click to copy. Last 100, in
`~/.local/state/text-polish/history.jsonl` on this computer only; Settings has
**Keep history** and **Clear history**.

## Refine
Press **/** (or the ✎ button by ↻) for a one-line field above the text: type a
one-off instruction such as "address it to Priya" and press **Enter**. Rewrite
and Reply rework the version on screen (keeping its tone), Read re-reads the
original with your request; either way it's a new version tagged "refined".
Esc closes the field. Its 📌 saves the instruction as a pin for the current
tone instead. Instructions are never read from the text itself: the selection
is untrusted, so `{{...}}`-style markup in it is just text.

## Changes view
**Changes** (Alt+D) shows a word-level diff of what the AI did to your text:
removed words struck through in red, added words highlighted, plus a count
("3 changes", or "No changes needed"). Proofread opens on it by default, so a
proofread can be checked at a glance. Click the text to go back to editing.

## Prepare next tone (optional)
With **Prepare next tone** on, after each rewrite Polish quietly generates the
next chip's tone in the background. It stays out of the pager until you pick
that chip, then appears instantly and the one after it starts preparing. It
costs one extra agent run per step, so it is **off by default**.

## Settings
The gear in the header (Alt+S or Ctrl+,) opens Settings:
- **Tone chips**: tap to show or hide a tone, drag to reorder the row, Reset
  to restore. Alt+1–8 follow the shown chips in your order; hidden tones still
  work from the browser menu and `apps.conf`.
- **Show changes**, **Open Proofread on changes**, **Prepare next tone**.

## Custom tones
Settings → **Custom tones** → **New tone**: give it a name (the chip label),
describe how it should sound, and optionally paste 3–10 messages you wrote
under **Sounds like me** so it copies your voice. Starter templates: Sounds like
me, LinkedIn post, Client update, Family chat. Up to 8; they behave like the
built-in tones (chip row, order, show/hide, Alt+number, pins, Reply mode,
prefetch). Ctrl+Enter saves. Stored in `settings.json` as `customTones`; the
browser menu lists only the built-in tones.

## Shortcut hints
Hold Alt for about a third of a second and small keycaps appear on each
control: 1–8 on the tone chips, A agent, M Rewrite/Reply, S settings,
J Adjust, D Changes, O Original. They vanish when you let go, and a quick
Alt+key press never flashes them. (No setting: they only show while you hold Alt.)

Saved per user in `~/.local/state/text-polish/settings.json` (not in this repo).

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
- **Pinned instructions.** The Adjust text box is one-time. To keep an
  instruction, click the pin in the box's corner: it becomes a small chip above
  the box (up to 3 per tone) and applies every time you pick that tone, in new
  popups too (the footer says "1 pin"). On a chip, the **pin icon** pauses or
  resumes it (paused pins stay saved), and the **words** open it in the box to
  edit, with delete and ✓ done. Pins are per mode and tone and live in
  `settings.json`.

## Layout
Tone chips sit in one row that scrolls sideways, with Adjust pinned on the
left. Scroll it with a touchpad swipe, the mouse wheel, a drag, or the ‹ ›
arrows at the edges: hover one to glide that way, click it to jump a page. The footer is one line; hover its ⓘ icon for the
keyboard shortcuts.

## Keys in the popup
Esc close · Ctrl+Enter replace (copy if the selection wasn't editable) ·
Ctrl+Shift+Enter insert · Ctrl+R regenerate · ←/→ versions · Alt+1–8 pick style · Alt+J adjust · Alt+M rewrite/reply/read · Alt+A next agent ·
Alt+D changes · Alt+S settings ·
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
