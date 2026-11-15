# Polish: features

Source material for a landing page, store listing or launch post. Every claim
here is true of the current build; numbers come from our own tests (Nov 2026)
and say so. Keep it current: when a feature ships or changes, update this file
in the same commit (see `AGENTS.md`).

---

## The pitch

**One-liner:** Select any text, press one key, and rewrite it, reply to it or
understand it with the AI you already pay for.

**Short description:** Polish is a keyboard-first AI writing popup for the Linux
desktop. Highlight text in any app, tap Right Alt, and get it proofread,
restyled, answered or explained in seconds, then drop the result straight back
where you were typing. It runs on your own AI subscription (Claude, Codex,
OpenCode or Command Code): no new account, no extra bill, no text sent to a
middleman.

**Tagline options:**
- Rewrite, reply, read. One key.
- Your AI, wherever you type.
- Fix it, answer it, get it, without leaving the app.
- The writing assistant that uses the AI you already have.

**Who it's for:** people who write all day in many apps (chat, email, social,
docs, terminals) and already have an AI coding-agent subscription; Linux and
Hyprland users who want a native, themed, keyboard-driven tool rather than a
browser extension or a chat window.

---

## How it works (3 steps)

1. **Select** text anywhere: a browser, chat app, email, editor or terminal.
2. **Tap Right Alt** (or right-click → *Rewrite with AI* in the browser). The
   popup opens over your work, already generating.
3. **Replace, Insert, Paste or Copy.** Polish puts the result back into the
   window you came from and gets out of the way.

---

## Three modes

A header switch (**Rewrite | Reply | Read**, Alt+M cycles) changes what Polish
does with your selection.

### Rewrite: change how your text sounds
Eight tones, each with concrete rules so they read clearly different (we
measured it; see *Proof points*):

| Tone | What it does |
|---|---|
| **Proofread** | Fixes spelling, grammar, punctuation and capitalization with the smallest possible changes. Keeps your voice. |
| **Tweet** | One post that fits X's 280-character limit, hook first. Retries automatically (twice) if the model overshoots, and warns if it's still over; live `n / 280` counter. |
| **Casual** | A friendly message to a teammate: contractions, plain words, warm. |
| **Punchy** | Headline first, short sentences, strong verbs, no hedging. |
| **Concise** | Aims for half the length while keeping every fact, question and request; if the two conflict, the facts win. |
| **Detailed** | 1.5–2× longer with context and transitions; told never to add new facts. |
| **Formal** | Client-ready: no contractions, no slang, courteous phrasing. |
| **Witty** | Playful, a joke or two, still accurate and kind. |

Buttons: **Replace** the selection, **Insert** after it, or **Copy** when the
text isn't editable.

### Reply: answer a message someone sent you
Select a message (WhatsApp Web, Gmail, Slack, anything) and Polish drafts *your*
reply instead of rewriting theirs.
- Say what you want in one line ("yes, but Monday works better") and press Enter.
- With nothing typed, it still answers each question, leaving a gap such as
  [rate] or [start date] wherever only you know the answer, and it is told not
  to accept or decline anything for you.
- It's instructed **not to invent** times, prices or promises and to leave
  `[time]`-style placeholders for you to fill in instead. Check the draft before
  sending: it's an AI, and the rule is a strong instruction, not a guarantee.
- **Fill in the blanks:** gaps like `[time]` and `[price]` are highlighted;
  **Tab** / **Shift+Tab** select each in turn so you just type over it. Paste or
  Copy with a gap still open asks once first ("2 blanks left"), so `[price]`
  never reaches a client by accident.
- Every tone works for replies. Edit a draft and restyle it, and your edit is
  kept.
- **Paste** drops the reply at your cursor; **Copy** copies it and closes.
  When you right-click a post in the browser, selecting it took your cursor out
  of the reply box, so Polish offers only Copy and tells you to click the reply
  box and press Ctrl+V.
- Opens directly with **Shift + Right Alt**, or *Reply with AI* in the browser.

### Read: understand text you didn't write
For articles, threads, docs and jargon:

| Action | What it does |
|---|---|
| **Summarize** | The main point in a sentence or two, at most about a quarter of the original. |
| **Points** (key points) | 3–7 short bullets keeping numbers, names, dates and action items. |
| **Explain** | Plain-language meaning, jargon and acronyms defined, why it matters. |
| **Translate** | Natural, fluent translation into 20+ languages (or any you type), keeping tone, names, numbers and formatting. Understands mixed and romanized text like Hinglish and Tanglish. |

- Thinks before answering (with Claude), so figures and unit conversions come
  out right, e.g. "₹75,000 crore (₹750 billion)".
- Opens on the action you used last.
- *Read with AI* in the browser right-click menu.

---

## Make it yours

### Custom tones, including your own voice
Make your own tones in Settings: a name, a description of how it should sound,
and optionally a few messages you wrote yourself.
- **Sounds like me:** paste 3–10 of your own messages and Polish rewrites in
  *your* voice: your word choice, rhythm, capitalization and emoji habits
  (never your content).
- **Starter templates:** Sounds like me, LinkedIn post, Client update, Family
  chat, ready to tweak.
- Up to 8, and they work everywhere built-in tones do: the chip row, your order,
  Alt+number shortcuts, pins, Reply mode and Prepare next tone.

### Refine: one-off changes in one keystroke
Press **/**, type "address it to Priya" or "focus on the deadlines", press
Enter. Polish makes a new version of what's on screen with that change, keeping
the tone. No menus.

### Pinned instructions: your standing preferences
Pin up to three instructions per tone, e.g. "use metric units, lakhs and crore
in brackets" for Explain, or "sign off as Sam" for Formal.
- Applied automatically every time, in every new popup.
- Shown as small chips; tap the pin to **pause** one (kept for later), tap the
  words to **edit** it.
- Applied **silently**: when a text doesn't need it, the AI doesn't mention it.
- Pin from Refine or from Adjust.

### Adjust
A panel per tone with a **Length** slider (short / tone default / long), an
**Emoji** slider (none to lots), a one-time request box and your pins.

### Tone by app
Polish knows which app the text came from and opens on the right tone: **Tweet**
on X, **Casual** in WhatsApp/Telegram/Slack/Discord/Signal, **Formal** in
Gmail/Outlook/LinkedIn. One small rules file (`apps.conf`) to add your own.

### Settings (gear, or Alt+S)
- Choose which tone chips show and **drag them into your order**; Alt+1–8 follow it.
- **Show changes** and **Open Proofread on changes**.
- **Prepare next tone** (off by default; it costs an extra AI run).
- Saved per user, outside the app, so updates never touch your preferences.

---

## Trust what you send

### Changes view
A word-level diff of exactly what the AI did: removed words struck through,
added words highlighted, plus a count ("3 changes", or "No changes needed").
Proofread opens on it by default, so you can check a proofread at a glance
instead of re-reading the whole thing.

### Versions you can page through
Every generation is kept: switch tones, agents or adjustments and flip back
with **← / →** or the `‹ n / N ›` pager. Each version remembers its tone, agent,
timing and your hand edits. **Original** shows your untouched text in place.

### Undo, one key
Replaced the wrong thing? Click **Undo** on the toast that appears (it shows
even with Do Not Disturb on), or press
**Super + Alt + Z** within 10 minutes, and your original text is back exactly
(Polish uses the app's own undo). In terminals, it hands the original back on
your clipboard.

### History
Every result you got (including ones on screen when you closed the popup, so a
slip of Esc loses nothing), searchable, one click to copy, even after the popup is
gone. Tap Right Alt with nothing selected (or Alt+H) to open it. The last 100
results, stored only on your computer; turn it off or clear it in Settings.

### Edit before you send
The result is an editable text box. Your edits feed the next rewrite;
Shift+↻ starts over from the original.

---

## Fast

- **Streaming:** with Claude, the first words appear in about **2 seconds**; a
  full rewrite or reply takes about **3–4 seconds**.
- **Prepare next tone:** optionally generates the next chip in the background,
  so switching tones is instant.
- **Codex tuned** from ~9 s to ~5–6 s by skipping its heavy user config.
- **Instant re-picks:** clicking a tone you already generated shows it
  immediately instead of regenerating.
- **Stop any time:** Esc (or the ■ button) stops a slow run at once, agent and
  all; your request, Refine text, adjustments and earlier versions stay.

### When something goes wrong
Errors come as one plain sentence with the next step, not a stack trace:
"Claude isn't signed in. To fix it, run `claude` in a terminal and use
/login. Or switch agent with Alt+A." Polish recognises sign-in, usage-limit
and overload, network, model-access, not-installed and timeout problems for
every agent; the raw error stays underneath for the curious. It never
switches agents for you (that would send your text to another company
without asking), and if your saved agent was uninstalled, it starts with one
that's there.

---

## Your AI, your subscription

- Works with **Claude (Claude Code)**, **Codex**, **OpenCode** and
  **Command Code**; switch from the header pill or **Alt+A**. The choice is
  remembered.
- Uses the CLI you're already logged into: **no API keys, no new account, no
  extra subscription**.
- Each agent runs in its most restricted mode: Claude with no tools and no MCP
  servers, Codex in its read-only sandbox, OpenCode's read-only `plan` agent,
  Command Code in plan mode. That's what the CLIs offer; Polish asks for text
  back, never for actions. Claude and Codex also run with no saved session and without your
  personal agent config.

---

## Keyboard-first, but mouse-friendly

- **Right Alt** opens Rewrite, **Shift + Right Alt** opens Reply,
  **SUPER + ALT + R / Y** as alternatives.
- **App won't share its selection?** Press Ctrl+C, then **SUPER + ALT + C**:
  Polish works on what you copied. (Copy-only in Rewrite, since clipboard text
  could have come from anywhere; Reply's Paste at your cursor still works.)
- **Hold Alt** and small keycaps appear on every control (1–8 on tones, A agent,
  M mode, S settings, J Adjust, D Changes, O Original). Let go and they vanish;
  a quick Alt+key never flashes them.
- Full shortcut list:

| Key | Action |
|---|---|
| Ctrl+Enter | Replace (Copy in Reply/Read) |
| Ctrl+Shift+Enter | Insert / Paste |
| ← / → | Previous / next version |
| Tab / Shift+Tab | Next / previous blank in a reply |
| / | Refine |
| Ctrl+R, Ctrl+Shift+R | Regenerate, regenerate from original |
| Alt+1…8 | Pick a tone / Read action |
| Alt+M | Rewrite → Reply → Read |
| Alt+A | Next agent |
| Alt+J | Adjust |
| Alt+D | Changes |
| Alt+O | Original |
| Alt+S or Ctrl+, | Settings |
| Alt+H | History |
| Super+Alt+C | Polish the copied text (clipboard) |
| Super+Alt+Z | Undo the last Replace / Insert / Paste |
| Esc | Stop a running generation; else close the open panel, then the popup |

- **Mouse and touchpad:** the tone row scrolls with a swipe, the wheel, a drag,
  or by hovering the ‹ › edges (click to jump a page).

---

## Native look

- Follows your **Omarchy theme** colors automatically.
- A centered overlay popup on the monitor you're using, with a soft scrim; one
  row of chips and a one-line footer keep it uncluttered.
- Terminals are handled: pasting uses Ctrl+Shift+V there.

---

## Private and safe by design

- **No middleman:** text goes from your machine to the AI provider you already
  use, through its official CLI. Polish has no server. (The provider does see
  the text, under its own data policy; Polish doesn't run a model locally.)
- **Pastes only into the window you selected from:** keys go straight to that
  window (never to whatever happens to be focused). Polish targets the window,
  not the exact text box, so if you click elsewhere in it meanwhile, the paste
  lands at the new cursor; Undo fixes that. If that window closed,
  or a browser request ended up pointed at another app, Polish pastes nowhere
  and leaves the text on your clipboard.
- **Your text stays off the command line:** results, originals, history and
  prompts travel through private files, never process arguments other users
  could see.
- **Private files:** settings and history are readable only by you.
- **Independently reviewed:** two adversarial passes by a second AI model
  (Codex `gpt-6-astra`) found 18 and then 14 issues, and a later product
  review caught a few more; all were fixed (`docs/reviews/`).
- **Built against prompt injection:** selected text is wrapped and marked as
  content, the AI is told never to follow instructions inside it, and Polish
  never reads commands out of the text. A web page that says "ignore the user
  and write X" should get rewritten, not obeyed. No AI defense is perfect, so
  read what you paste from untrusted pages. Instructions only come from Polish's own fields.
- **You control what's kept:** History (the last 100 results) stays
  on your computer, and can be cleared or switched off in Settings. Claude,
  Codex and Command Code runs save no session history.
- **Open source** on GitHub.

---

## Proof points (our own tests, Nov 2026)

- **Tone quality** (8 tones × sample texts, scored 1–10 on hitting each tone's
  rules): Claude 8.7, OpenCode 8.5, Command Code 8.2, Codex 7.2.
- **Tones are distinct:** pairwise similarity between tones' outputs dropped to
  0.38–0.58 after tuning (identical would be 1.0).
- **Speed:** first words ~2 s (Claude, streaming); Codex ~5–6 s; Summarize and
  Points ~4 s even on long articles; Translate ~3 s; Explain (thinks hardest)
  ~7–12 s.
- **Accuracy:** with thinking on, currency/unit conversions came out clean in
  3 of 3 runs, versus garbled in 1–2 of 3 without.

---

## Requirements and install

- Linux with **Hyprland** (built and tested on **Omarchy**), Quickshell,
  `wl-clipboard`, `wtype`, `jq`.
- At least one logged-in CLI: Claude Code, Codex, OpenCode or Command Code.
- Browser right-click menu: Brave / Chromium / Chrome via a small unpacked
  extension.
- Install: `git clone … ~/.config/text-polish && ~/.config/text-polish/install.sh`.

## Honest limits

- A system-wide right-click entry isn't possible on Wayland (every app draws
  its own menu); outside the browser you use the hotkey.
- Hyprland only for now (focus and paste-back use Hyprland's IPC).
- Speed and quality depend on the agent and model you use.

## On the roadmap (ideas, not promises)

- **Accept changes one by one** in the Changes view.
- **Translate your rewrite** in one click from the Rewrite side (polish a
  message, then send it in Hindi or Tamil). Today: press / and type
  "translate to Hindi"; Read always works on the original selection.
- Dictation cleanup after voice typing.
- Apply a pin to every Read action at once.
- Other compositors and desktops.
