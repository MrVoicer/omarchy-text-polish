// Polish — AI rewrite popup for selected text (standalone Quickshell config).
// Launched by ./polish; env: POLISH_INPUT, POLISH_STYLE, POLISH_EDITABLE,
// POLISH_WINDOW, POLISH_MONITOR, POLISH_DIR.
//
// Every generation is kept as a numbered version (< n / N > pager, Left/Right
// keys). The Adjust panel generates a new version with a tone plus length,
// emoji and a free-text request; its settings are remembered per tone.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string dir: Quickshell.env("POLISH_DIR") || ""
  readonly property string inputPath: Quickshell.env("POLISH_INPUT") || ""
  readonly property string windowAddr: Quickshell.env("POLISH_WINDOW") || ""
  readonly property bool editable: (Quickshell.env("POLISH_EDITABLE") || "unknown") !== "no"

  readonly property var styles: [
    { key: "proofread", label: "Proofread" },
    { key: "tweet", label: "Tweet" },
    { key: "casual", label: "Casual" },
    { key: "punchy", label: "Punchy" },
    { key: "concise", label: "Concise" },
    { key: "detailed", label: "Detailed" },
    { key: "formal", label: "Formal" },
    { key: "witty", label: "Witty" }
  ]
  // ---- settings (per user, outside the repo) ------------------------------
  // order: all tones in your row order. tones: which of them show.
  // showChanges: the Changes view (#4).
  // autoChanges: Proofread opens on Changes. prefetch: prepare the next tone
  // in the background so switching is instant (costs an extra agent run).
  readonly property string settingsPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/text-polish/settings.json"
  readonly property var defaultSettings: ({ order: styles.map(function(t) { return t.key }), tones: styles.map(function(t) { return t.key }),
                                            showChanges: true, autoChanges: true, prefetch: false })
  property var settings: defaultSettings
  function setting(k) { return settings[k] !== undefined ? settings[k] : defaultSettings[k] }
  function setSetting(k, val) {
    var o = Object.assign({}, settings)
    o[k] = val
    settings = o
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1.tmp" && mv "$1.tmp" "$1"',
                             "sh", settingsPath, JSON.stringify(o, null, 2)])
  }
  FileView {
    path: root.settingsPath
    blockLoading: true
    onLoaded: {
      try {
        var o = JSON.parse(text())
        if (o && typeof o === "object") root.settings = Object.assign({}, root.defaultSettings, o)
      } catch (e) {}
    }
  }
  // All tones in your order (unknown keys dropped, new tones appended).
  readonly property var orderedStyles: {
    var o = setting("order"), out = []
    o.forEach(function(k) { var t = styleByKey(k); if (t && out.indexOf(t) < 0) out.push(t) })
    styles.forEach(function(t) { if (out.indexOf(t) < 0) out.push(t) })
    return out
  }
  function styleByKey(k) {
    for (var i = 0; i < styles.length; i++) if (styles[i].key === k) return styles[i]
    return null
  }
  // Chips shown, in your order (hidden tones still work from apps.conf/the browser menu).
  readonly property var tones: {
    var on = setting("tones")
    var t = orderedStyles.filter(function(x) { return on.indexOf(x.key) >= 0 })
    return t.length ? t : orderedStyles
  }
  // Drag-to-reorder in Settings: move the tone at index `from` to slot `to` (0..n).
  function moveTone(from, to) {
    var o = orderedStyles.map(function(t) { return t.key })
    if (from < 0 || from >= o.length || to === from || to === from + 1) return
    var k = o.splice(from, 1)[0]
    o.splice(to > from ? to - 1 : to, 0, k)
    setSetting("order", o)
  }
  function resetTones() {
    var o = Object.assign({}, settings)
    o.order = defaultSettings.order; o.tones = defaultSettings.tones
    settings = o
    setSetting("order", defaultSettings.order)
  }

  // Hold Alt (~0.3s, so quick Alt+key combos don't flash) to see shortcut hints.
  property bool altHeld: false
  Timer { id: altTimer; interval: 300; onTriggered: root.altHeld = true }
  function altDown() { if (!altHeld && !altTimer.running) altTimer.start() }
  function altUp() { altTimer.stop(); altHeld = false }
  function toggleTone(k) {
    var on = setting("tones").slice()
    var i = on.indexOf(k)
    if (i >= 0) { if (on.length > 1) on.splice(i, 1) } else on.push(k)
    setSetting("tones", on)
  }

  // Read mode's own chips: understand text you didn't write.
  readonly property var readStyles: [
    { key: "summarize", label: "Summarize" },
    { key: "keypoints", label: "Key points" },
    { key: "explain", label: "Explain" }
  ]
  readonly property var modes: [{ key: "rewrite", label: "Rewrite" }, { key: "reply", label: "Reply" }, { key: "read", label: "Read" }]
  // "rewrite": restyle the selection. "reply": draft a reply to the selected message.
  // "read": summarize or explain it.
  property string mode: ["reply", "read"].indexOf(Quickshell.env("POLISH_MODE_START")) >= 0 ? Quickshell.env("POLISH_MODE_START") : "rewrite"
  // Chips for the current mode (rewrite and reply share your tone row).
  readonly property var modeTones: mode === "read" ? readStyles : tones
  property string intent: ""                // Reply mode: what you want to say
  function styleLabel(k) {
    if (k === "proofread" && mode === "reply") return "Standard"
    for (var i = 0; i < styles.length; i++) if (styles[i].key === k) return styles[i].label
    for (var j = 0; j < readStyles.length; j++) if (readStyles[j].key === k) return readStyles[j].label
    return k
  }

  readonly property var lengthStops: ["Short", "Moderate", "Long"]          // Moderate = the tone's own length
  readonly property var lengthArgs: ["short", "", "long"]
  readonly property var emojiStops: ["None", "Few", "Moderate", "Lots"]
  readonly property var emojiArgs: ["none", "few", "moderate", "lots"]

  // ---- versions -----------------------------------------------------------
  // Each: { id, style, agent, agentLabel, length, emoji, note, source, edited, busy, ok, text, ms, startedAt }
  // source: text this version rewrote ("" = the original selection); edited: you changed its text.
  property var versions: []
  property int vi: -1                       // index of the version on screen
  property int nextId: 1
  property string style: Quickshell.env("POLISH_STYLE") || "proofread"
  readonly property var current: vi >= 0 && vi < versions.length ? versions[vi] : null
  readonly property bool busy: !current || current.busy
  readonly property bool anyBusy: versions.some(function(v) { return v.busy })

  property real now: Date.now()
  Timer { interval: 100; repeat: true; running: root.anyBusy; onTriggered: root.now = Date.now() }
  function fmtSecs(ms) { return (ms / 1000).toFixed(1) + "s" }

  property bool showOriginal: false
  property bool showDiff: false             // Changes view: what the AI edited (#4)
  readonly property bool diffAvailable: setting("showChanges") && !!current && !current.busy && current.ok && current.mode === "rewrite"
  // Proofread opens on its changes (setting), unless you've edited it by hand.
  function autoDiffFor(v) {
    return !!v && setting("showChanges") && setting("autoChanges") && v.mode === "rewrite"
           && v.style === "proofread" && !v.busy && v.ok && !v.edited
  }
  function toggleDiff() {
    if (!diffAvailable) return
    showOriginal = false
    showDiff = !showDiff
    if (!showDiff) blurText()
  }

  // Word-level diff of the text a version rewrote vs. its (possibly edited) result,
  // as rich text: removed words struck through, added words highlighted.
  function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
  function diffHtml(a, b) {
    a = a.replace(/\s+$/, ""); b = b.replace(/\s+$/, "")   // a trailing newline isn't an edit
    var A = a.match(/\s+|[^\s]+/g) || [], B = b.match(/\s+|[^\s]+/g) || []
    var pre = 0
    while (pre < A.length && pre < B.length && A[pre] === B[pre]) pre++
    var suf = 0
    while (suf < A.length - pre && suf < B.length - pre && A[A.length - 1 - suf] === B[B.length - 1 - suf]) suf++
    var a2 = A.slice(pre, A.length - suf), b2 = B.slice(pre, B.length - suf)
    var n = a2.length, m = b2.length, ops = []
    if (n * m > 4000000) {                   // too big to align word by word: one block each
      if (n) ops.push(["-", a2.join("")])
      if (m) ops.push(["+", b2.join("")])
    } else {
      // LCS table, then walk it forward.
      var w = m + 1, L = new Int32Array((n + 1) * w)
      for (var i = n - 1; i >= 0; i--)
        for (var j = m - 1; j >= 0; j--)
          L[i * w + j] = a2[i] === b2[j] ? L[(i + 1) * w + j + 1] + 1 : Math.max(L[(i + 1) * w + j], L[i * w + j + 1])
      var x = 0, y = 0
      while (x < n || y < m) {
        if (x < n && y < m && a2[x] === b2[y]) { ops.push(["=", a2[x]]); x++; y++ }
        else if (x < n && (y >= m || L[(x + 1) * w + y] >= L[x * w + y + 1])) { ops.push(["-", a2[x]]); x++ }
        else { ops.push(["+", b2[y]]); y++ }
      }
    }
    // Merge runs of the same kind; edits split only by whitespace count as one change.
    var runs = []
    ops.forEach(function(o) {
      var last = runs[runs.length - 1]
      if (last && last[0] === o[0]) last[1] += o[1]; else runs.push([o[0], o[1]])
    })
    var out = esc(A.slice(0, pre).join("")), count = 0, inChange = false
    for (var r = 0; r < runs.length; r++) {
      var k = runs[r][0], t = runs[r][1]
      if (k === "=") {
        if (!/^\s+$/.test(t)) inChange = false
        out += esc(t)
      } else {
        if (!inChange) count++
        inChange = true
        if (k === "-") out += '<s><span style="color:' + rgba(danger, 1) + ';">' + esc(t) + '</span></s>'
        else out += '<span style="color:' + rgba(accent, 1) + '; background-color:' + rgba(accent, 0.2) + ';">' + esc(t) + '</span>'
      }
    }
    out += esc(A.slice(A.length - suf).join(""))
    return { html: '<div style="white-space:pre-wrap;">' + out + '</div>', count: count }
  }
  function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }
  readonly property var diff: showDiff && current && !current.busy ? diffHtml(diffBase(current), editor.text) : ({ html: "", count: 0 })
  function diffBase(v) { return v && v.source ? v.source : original }
  property bool copied: false
  property string view: "main"              // "main" | "adjust"
  readonly property string original: inputFile.text()

  // Adjust panel state, remembered per tone: style -> { length, emoji, note }
  property var adjustByStyle: ({})
  property string adjStyle: style
  property int adjLength: 1
  property int adjEmoji: 0
  function adjustFor(s) { return adjustByStyle[s] || { length: 1, emoji: 0, note: "" } }

  // Pinned instructions: up to maxPins saved per mode+tone (settings.json "pins"),
  // each { text, on }. On pins apply to every generation of that tone, in new
  // popups too; off pins stay saved for later. The Adjust text box is one-time.
  readonly property int maxPins: 3
  function pinKey(s) { return mode + ":" + s }
  function pinsFor(s) {
    var p = (setting("pins") || {})[pinKey(s)]
    if (!p) return []
    if (!Array.isArray(p)) return p.note ? [{ text: p.note, on: true }] : []   // old single-pin format
    return p
  }
  function setPins(s, list) {
    var p = Object.assign({}, setting("pins") || {})
    if (list.length) p[pinKey(s)] = list; else delete p[pinKey(s)]
    setSetting("pins", p)
  }
  function activePinText(s) {
    return pinsFor(s).filter(function(x) { return x.on && x.text.trim() }).map(function(x) { return x.text.trim() })
  }
  function addPin(s, text) {
    var l = pinsFor(s).slice()
    if (!text.trim() || l.length >= maxPins) return false
    l.push({ text: text.trim(), on: true })
    setPins(s, l)
    return true
  }
  function togglePin(s, i) {
    var l = pinsFor(s).map(function(x) { return Object.assign({}, x) })
    if (i < 0 || i >= l.length) return
    l[i].on = !l[i].on
    setPins(s, l)
  }
  function updatePin(s, i, text) {
    var l = pinsFor(s).map(function(x) { return Object.assign({}, x) })
    if (i < 0 || i >= l.length) return
    l[i].text = text
    setPins(s, l)
  }
  function deletePin(s, i) {
    var l = pinsFor(s).slice()
    l.splice(i, 1)
    setPins(s, l)
  }
  function pinPreview(t) {
    var w = t.trim().split(/\s+/)
    return w.length > 4 ? w.slice(0, 4).join(" ") + "\u2026" : t.trim()
  }

  // Editing a pin in the Adjust box: the one-time text is set aside meanwhile.
  property int editingPin: -1
  property string stashedNote: ""
  function editPin(i) {
    if (editingPin === i) { stopEditingPin(); return }
    if (editingPin < 0) stashedNote = adjustNote.text
    editingPin = i
    adjustNote.text = pinsFor(adjStyle)[i].text
    adjustNote.forceActiveFocus()
    adjustNote.cursorPosition = adjustNote.length
  }
  function stopEditingPin() {
    if (editingPin < 0) return
    var t = adjustNote.text.trim()
    if (!t) deletePin(adjStyle, editingPin); else updatePin(adjStyle, editingPin, t)
    editingPin = -1
    adjustNote.text = stashedNote
  }
  function deleteEditingPin() {
    var i = editingPin
    editingPin = -1
    deletePin(adjStyle, i)
    adjustNote.text = stashedNote
  }
  function pinBoxText() {
    if (addPin(adjStyle, adjustNote.text)) adjustNote.text = ""
  }

  // ---- agent picker -------------------------------------------------------
  property var agents: []
  property string agent: ""
  property bool agentMenu: false
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/text-polish/agent"
  function labelForAgent(id) {
    for (var i = 0; i < agents.length; i++) if (agents[i].id === id) return agents[i].label
    return id || "Agent"
  }
  readonly property string agentLabel: labelForAgent(agent)

  Process {
    id: agentList
    command: [root.dir + "/rewrite.sh", "--list-agents"]
    stdout: StdioCollector {
      onStreamFinished: {
        var list = [], cur = ""
        text.split("\n").forEach(function(line) {
          var f = line.split("\t")
          if (f.length < 2) return
          if (f[0] === "current") cur = f[1]
          else list.push({ id: f[0], label: f[1] })
        })
        root.agents = list
        root.agent = cur
        if (root.mode === "read" && !root.isReadStyle(root.style)) root.style = root.lastRead()
        root.generate(root.style, {})
      }
    }
  }

  function setAgent(id) {
    agentMenu = false
    if (id === agent) return
    agent = id
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "sh", statePath, id])
    // New agent: add a version of the same tone and adjustments; older versions stay.
    var c = at()
    generate(c ? c.style : style, c ? { length: c.length, emoji: c.emoji, note: c.note, intent: c.intent } : {})
  }

  function cycleAgent() {
    if (agents.length < 2) return
    var i = 0
    for (; i < agents.length; i++) if (agents[i].id === agent) break
    setAgent(agents[(i + 1) % agents.length].id)
  }

  // ---- theme (Omarchy current theme) --------------------------------------
  property var theme: ({})
  function c(name, fallback) { return theme[name] || fallback }
  FileView {
    id: themeFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    blockLoading: true
    onLoaded: {
      var t = {}, re = /^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm, m
      var s = text()
      while ((m = re.exec(s)) !== null) t[m[1]] = m[2]
      root.theme = t
    }
  }
  readonly property color bg: c("background", "#1e1e1e")
  readonly property color surface: c("lighter_background", "#2a2a2a")
  readonly property color surface2: c("selection", "#3a3a3a")
  readonly property color fg: c("foreground", "#e0e0e0")
  readonly property color dim: c("light_foreground", "#9a9a9a")
  readonly property color faint: c("muted", "#555555")
  readonly property color accent: c("accent", "#7fbbb3")
  readonly property color danger: c("red", "#e67e80")
  readonly property string font: "JetBrainsMono Nerd Font"

  FileView { id: inputFile; path: root.inputPath; blockLoading: true }

  // ---- agent jobs ---------------------------------------------------------
  Component {
    id: jobComp
    Process {
      id: job
      property int versionId
      // rewrite.sh line protocol (POLISH_STREAM=1): P/R/F/E, see its header.
      stdout: SplitParser { onRead: (line) => root.jobLine(job.versionId, line) }
      onExited: { root.jobExited(job.versionId); job.destroy() }
    }
  }

  // opts: { length: "short"|"long"|"", emoji: "none"|"few"|"moderate"|"lots"|"", note: string }
  // What the next generation rewrites: your edited text if you changed the
  // version on screen, otherwise whatever that version was rewritten from.
  function baseSource(fromOriginal) {
    if (fromOriginal || mode === "reply") return ""     // a reply always answers the original message
    var c = at()
    if (!c || c.mode !== "rewrite") return ""
    if (c.ok && c.edited && c.text.trim() !== "") return c.text
    return c.source || ""
  }

  // Reply mode: an edited reply on screen is sent along as your draft to restyle.
  function replyDraft(fromOriginal) {
    if (mode !== "reply" || fromOriginal) return ""
    var c = at()
    return c && c.mode === "reply" && c.ok && c.edited ? c.text : ""
  }

  // Prefetched versions wait here, out of the pager, until you pick their tone.
  property var prefetched: []

  function generate(s, opts) {
    var pins = activePinText(s)      // pinned instructions apply to every generation of this tone
    var v = {
      id: nextId++, style: s, agent: agent, agentLabel: agentLabel,
      length: opts.length || "", emoji: opts.emoji || "", note: (opts.note || "").trim(), pins: pins,
      source: opts.source !== undefined ? opts.source : baseSource(opts.fromOriginal), edited: false, refined: !!opts.refined,
      mode: mode, intent: mode === "reply" ? (opts.intent !== undefined ? opts.intent : intent).trim() : "",
      draft: opts.draft !== undefined ? opts.draft : replyDraft(opts.fromOriginal), partial: "",
      busy: true, ok: false, text: "", ms: 0, startedAt: Date.now(), bg: !!opts.background
    }
    if (v.bg) {
      prefetched = prefetched.concat([v])
    } else {
      noteReadUse(s)
      versions = versions.concat([v])
      style = s
      showOriginal = false
      showDiff = false
      copied = false
      now = Date.now()
      vi = versions.length - 1
    }
    var env = { POLISH_LENGTH: v.length, POLISH_EMOJI: v.emoji, POLISH_NOTE: v.pins.concat(v.note ? [v.note] : []).join("\n"), POLISH_SOURCE_TEXT: v.source,
                POLISH_MODE: v.mode, POLISH_INTENT: v.intent, POLISH_DRAFT: v.draft, POLISH_STREAM: "1" }
    if (agent) env.POLISH_AGENT = agent
    var j = jobComp.createObject(root, { versionId: v.id, environment: env,
      command: [dir + "/rewrite.sh", s, inputPath] })
    j.running = true
  }

  function indexOfVersion(id) {
    for (var i = 0; i < versions.length; i++) if (versions[i].id === id) return i
    return -1
  }

  function prefetchOf(id) {
    for (var i = 0; i < prefetched.length; i++) if (prefetched[i].id === id) return prefetched[i]
    return null
  }
  // A prefetched job finishing before you pick its tone: just record the result.
  function finishBg(v, ok, text) {
    v.busy = false; v.ms = Date.now() - v.startedAt; v.ok = ok
    v.text = ok ? text : String(text).trim(); v.partial = ""
    if (!ok) prefetched = prefetched.filter(function(x) { return x !== v })   // retry for real if picked
  }

  function jobLine(id, line) {
    var kind = line.charAt(0), payload = line.length > 2 ? line.slice(2) : ""
    var value = ""
    if (payload) { try { value = JSON.parse(payload) } catch (e) { return } }
    var i = indexOfVersion(id)
    if (i < 0) {
      var b = prefetchOf(id)
      if (!b || !b.busy) return
      if (kind === "P") b.partial += value
      else if (kind === "R") b.partial = ""
      else if (kind === "F" || kind === "E") finishBg(b, kind === "F", kind === "F" ? value : (value || "Rewrite failed."))
      return
    }
    if (!versions[i].busy) return
    if (kind === "P" || kind === "R") {
      // Streaming text: mutate in place (no list copy per chunk) and paint it.
      var v = versions[i]
      v.partial = kind === "R" ? "" : v.partial + value
      if (i === vi) { loadingEditor = true; editor.text = v.partial; loadingEditor = false }
      if (!streaming) streaming = true
    } else if (kind === "F" || kind === "E") {
      finish(i, kind === "F", kind === "F" ? value : (value || "Rewrite failed."))
    }
  }

  function jobExited(id) {
    var i = indexOfVersion(id)
    if (i >= 0 && versions[i].busy) finish(i, false, "The agent exited without an answer.")
    var b = i < 0 ? prefetchOf(id) : null
    if (b && b.busy) finishBg(b, false, "The agent exited without an answer.")
  }

  function finish(i, ok, text) {
    var list = versions.slice()
    var v = Object.assign({}, list[i])
    v.busy = false
    v.ms = Date.now() - v.startedAt
    v.ok = ok
    v.text = ok ? text : String(text).trim()
    v.partial = ""
    list[i] = v
    versions = list
    if (i === vi) { showVersion(); showDiff = autoDiffFor(v) }
    if (ok) maybePrefetch(v)
  }

  // ---- prefetch (#8b) -----------------------------------------------------
  // After a rewrite you asked for, quietly generate the next chip's tone.
  function maybePrefetch(v) {
    if (!setting("prefetch") || v.mode !== "rewrite" || mode !== "rewrite") return
    var t = tones, k = -1
    for (var i = 0; i < t.length; i++) if (t[i].key === v.style) k = i
    for (var n = 1; n < t.length; n++) {
      var s = t[(k + n) % t.length].key
      if (hasVersion(s) || findPrefetch(s)) continue
      generate(s, { background: true })
      return
    }
  }
  function hasVersion(s) {
    for (var i = 0; i < versions.length; i++) if (versions[i].style === s && versions[i].mode === mode) return true
    return false
  }
  // Only a prefetch made for what a fresh pick would rewrite now (same agent, same source).
  function findPrefetch(s) {
    var src = baseSource(false)
    for (var i = 0; i < prefetched.length; i++) {
      var b = prefetched[i]
      if (b.style === s && b.mode === mode && b.agent === agent && b.source === src) return b
    }
    return null
  }
  property bool streaming: false    // bumps bindings that depend on partial text

  // Load the on-screen version into the editor (its text may have been edited).
  property bool loadingEditor: false
  // Read versions[vi] directly: inside onViChanged the `current` binding may not have updated yet.
  function at() { return vi >= 0 && vi < versions.length ? versions[vi] : null }
  function showVersion() {
    var v = at()
    loadingEditor = true
    editor.text = !v ? "" : v.busy ? (v.partial || "") : v.text
    if (v && !v.busy) editor.cursorPosition = 0      // finished: show it from the top
    loadingEditor = false
    copied = false
  }
  onViChanged: {
    var v = at()
    if (v) { style = v.style; mode = v.mode; if (v.mode === "reply") intent = v.intent }
    showVersion()
    showDiff = autoDiffFor(v)
    if (view === "main") blurText()
  }

  function go(delta) {
    var n = vi + delta
    if (n < 0 || n >= versions.length) return
    showOriginal = false
    vi = n
  }

  // Chip: jump to the latest version of that tone, or generate one.
  function pick(s) {
    noteReadUse(s)
    showOriginal = false
    for (var i = versions.length - 1; i >= 0; i--) {
      if (versions[i].style === s && versions[i].mode === mode) { vi = i; style = s; return }
    }
    var b = findPrefetch(s)
    if (b) {
      prefetched = prefetched.filter(function(x) { return x !== b })
      b.bg = false
      versions = versions.concat([b])
      style = s
      copied = false
      vi = versions.length - 1
      if (!b.busy) maybePrefetch(b)
      return
    }
    generate(s, {})
  }

  // Each side keeps its own last chip: Read has its own; Rewrite and Reply share tones.
  property string lastReadStyle: ""         // this popup's; falls back to the saved last-used one
  // Read opens on the action you used last (saved as "lastRead" in settings.json).
  function isReadStyle(k) { return readStyles.some(function(t) { return t.key === k }) }
  function lastRead() { var k = setting("lastRead"); return isReadStyle(k) ? k : "summarize" }
  function noteReadUse(s) { if (mode === "read" && isReadStyle(s) && setting("lastRead") !== s) setSetting("lastRead", s) }
  property string lastToneStyle: ""         // set when leaving Rewrite/Reply (plain value, not a binding)
  function setMode(m) {
    if (m === mode) return
    if (mode === "read") lastReadStyle = style; else lastToneStyle = style
    mode = m
    agentMenu = false
    pick(m === "read" ? (lastReadStyle || lastRead()) : (lastToneStyle || "proofread"))   // that chip's latest version in this mode, or a new one
  }
  function cycleMode() {
    var i = 0
    for (; i < modes.length; i++) if (modes[i].key === mode) break
    setMode(modes[(i + 1) % modes.length].key)
  }

  function draftReply() {
    blurText()
    var c = at()
    generate(style, c ? { length: c.length, emoji: c.emoji, note: c.note, intent: intent } : { intent: intent })
  }

  function toneByIndex(i) {
    if (i >= modeTones.length) return
    var k = modeTones[i].key
    if (view === "adjust") switchAdjustTone(k); else pick(k)
  }

  // fromOriginal (Shift+click or Ctrl+Shift+R): rewrite the original selection, ignoring edits.
  // ---- refine (/ key) ------------------------------------------------------
  // A one-off instruction applied to the version on screen: Rewrite and Reply
  // rework that version's text; Read re-reads the original with the request.
  property bool refineOpen: false
  property string pinnedFlash: ""
  Timer { id: pinnedFlashTimer; interval: 1800; onTriggered: root.pinnedFlash = "" }
  function openRefine() {
    if (view !== "main") return
    agentMenu = false
    refineOpen = true
    refineField.forceActiveFocus()
  }
  function closeRefine() { refineOpen = false; refineField.text = ""; blurText() }
  function refine(text) {
    text = text.trim()
    var c = at()
    if (!text || !c || c.busy) return
    var o = { length: c.length, emoji: c.emoji, note: text, intent: c.intent, refined: true }
    if (c.ok && c.mode === "rewrite") o.source = c.text
    if (c.ok && c.mode === "reply") o.draft = c.text
    closeRefine()
    generate(c.style, o)
  }
  function pinRefine() {
    var t = refineField.text.trim()
    if (!t) return
    if (addPin(style, t)) {
      refineField.text = ""
      pinnedFlash = "Pinned for " + styleLabel(style) + ": applies from the next version"
    } else pinnedFlash = "Up to " + maxPins + " pins per tone (manage them in Adjust)"
    pinnedFlashTimer.restart()
  }

  function regenerate(fromOriginal) {
    var c = at()
    var o = c ? { length: c.length, emoji: c.emoji, note: c.note, intent: c.intent } : {}
    o.fromOriginal = !!fromOriginal
    generate(c ? c.style : style, o)
  }

  function toggleOriginal() {
    showDiff = false
    showOriginal = !showOriginal
  }
  function openSettings() {
    agentMenu = false
    if (view === "adjust") saveAdjust()
    view = view === "settings" ? "main" : "settings"
    blurText()
  }

  // ---- adjust panel -------------------------------------------------------
  function closeAdjust() { stopEditingPin(); saveAdjust(); view = "main" }
  function openAdjust() {
    agentMenu = false
    loadAdjust(style)
    view = "adjust"
  }
  function saveAdjust() {
    var m = Object.assign({}, adjustByStyle)
    m[adjStyle] = { length: adjLength, emoji: adjEmoji, note: adjustNote.text }
    adjustByStyle = m
  }
  function loadAdjust(s) {
    var a = adjustFor(s)
    adjStyle = s
    adjLength = a.length
    adjEmoji = a.emoji
    adjustNote.text = a.note
  }
  function switchAdjustTone(s) {
    if (s === adjStyle) return
    stopEditingPin()
    saveAdjust()
    loadAdjust(s)
  }
  function generateAdjusted() {
    stopEditingPin()
    saveAdjust()
    view = "main"
    generate(adjStyle, { length: lengthArgs[adjLength], emoji: mode === "read" ? "" : emojiArgs[adjEmoji], note: adjustNote.text })
  }

  function versionTags(v) {
    if (!v) return ""
    var t = [v.mode === "reply" ? "Reply, " + (v.style === "proofread" ? "Standard" : styleLabel(v.style))
           : v.mode === "read" ? "Read, " + styleLabel(v.style) : styleLabel(v.style)]
    if (v.intent) t.push("\u201C" + (v.intent.length > 24 ? v.intent.slice(0, 23) + "\u2026" : v.intent) + "\u201D")
    if (v.draft) t.push("from your draft")
    if (v.refined) t.push("refined")
    else if (v.source) t.push("from your edit")
    if (v.edited) t.push("edited")
    if (v.length) t.push(v.length === "short" ? "short" : "long")
    if (v.emoji) t.push(v.emoji === "none" ? "no emoji" : v.emoji + " emoji")
    if (v.note) t.push("“" + (v.note.length > 28 ? v.note.slice(0, 27) + "…" : v.note) + "”")
    if (v.pins && v.pins.length) t.push(v.pins.length === 1 ? "1 pin" : v.pins.length + " pins")
    return t.join(", ")
  }

  function busyVerb() {
    var v = current, m = v ? v.mode : mode, st = v ? v.style : style
    if (m === "reply") return "Drafting reply"
    if (m === "read") return st === "explain" ? "Explaining" : st === "keypoints" ? "Finding key points" : "Summarizing"
    return "Rewriting"
  }

  // ---- actions ------------------------------------------------------------
  // Clicking anything but a text box takes the cursor out of the text, so the
  // Left/Right arrows go back to paging versions.
  function blurText() { focusSink.forceActiveFocus() }

  function finalText() { return editor.text }

  function copy() {
    if (busy || !current.ok) return
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", finalText()])
    copied = true
    copiedTimer.restart()
  }

  function apply(how) {
    if (busy || !current.ok) return
    Quickshell.execDetached([dir + "/apply.sh", how, windowAddr, finalText()])
    Qt.quit()
  }

  function copyAndClose() {
    if (busy || !current.ok) return
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", finalText()])
    Qt.quit()
  }

  Timer { id: copiedTimer; interval: 1400; onTriggered: root.copied = false }

  Component.onCompleted: agentList.running = true

  // ---- UI components ------------------------------------------------------
  // Small keycap badge on a control's top-right corner, shown while Alt is held.
  component KeyHint: Rectangle {
    property string k
    visible: opacity > 0 && k !== ""
    opacity: root.altHeld && k !== "" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    z: 20
    anchors { top: parent.top; right: parent.right; topMargin: -5; rightMargin: -3 }
    width: Math.max(17, hintText.implicitWidth + 8); height: 17; radius: 6
    color: root.surface2
    border.width: 1
    border.color: Qt.alpha(root.fg, 0.18)
    Text {
      id: hintText
      anchors.centerIn: parent
      text: parent.k
      textFormat: Text.PlainText
      color: Qt.alpha(root.fg, 0.75)
      font.family: root.font; font.pixelSize: 10; font.weight: Font.DemiBold
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label
    property string glyph: ""
    property string hint: ""
    property bool active
    signal clicked
    implicitWidth: chipRow.implicitWidth + 32
    implicitHeight: 38
    radius: 19
    color: active ? Qt.alpha(root.accent, 0.16) : (chipMouse.containsMouse ? root.surface2 : root.surface)
    border.width: active ? 1.5 : 0
    border.color: root.accent
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 8
      Text {
        visible: chip.glyph !== ""
        text: chip.glyph
        textFormat: Text.PlainText
        color: chip.active ? root.accent : root.fg
        font.family: root.font
        font.pixelSize: 15
      }
      Text {
        text: chip.label
        textFormat: Text.PlainText
        color: chip.active ? root.accent : root.fg
        font.family: root.font
        font.pixelSize: 14
      }
    }
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); chip.clicked() } }
    KeyHint { k: chip.hint }
  }

  component IconButton: Rectangle {
    id: ib
    property string glyph
    property string hint: ""
    signal clicked(int mods)
    width: 38; height: 38; radius: 19
    color: ibMouse.containsMouse && ib.enabled ? root.surface2 : root.surface
    opacity: enabled ? 1 : 0.4
    Text { anchors.centerIn: parent; text: ib.glyph; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 16 }
    MouseArea { id: ibMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (m) => { root.blurText(); if (ib.enabled) ib.clicked(m.modifiers) } }
    KeyHint { k: ib.hint }
  }

  component ActionButton: Rectangle {
    id: ab
    property string label
    property bool primary
    signal clicked
    Layout.fillWidth: true
    implicitHeight: 46
    radius: 23
    color: primary ? (abMouse.containsMouse ? Qt.lighter(root.fg, 1.08) : root.fg)
                   : (abMouse.containsMouse ? root.surface2 : root.surface)
    opacity: enabled ? 1 : 0.45
    Text {
      anchors.centerIn: parent
      text: ab.label
      textFormat: Text.PlainText
      color: ab.primary ? root.bg : root.fg
      font.family: root.font
      font.pixelSize: 15
      font.weight: ab.primary ? Font.DemiBold : Font.Normal
    }
    MouseArea { id: abMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (ab.enabled) ab.clicked() }
  }

  // Stepped slider: a pill track with a dot per stop and a round knob.
  component StepSlider: Rectangle {
    id: ss
    property var stops: []
    property int value: 0
    property string glyph: ""
    signal moved(int v)
    readonly property real pad: 23
    readonly property real step: stops.length > 1 ? (width - 2 * pad) / (stops.length - 1) : 0
    Layout.fillWidth: true
    implicitHeight: 46
    radius: 23
    color: root.surface
    Repeater {
      model: ss.stops.length
      Rectangle {
        required property int index
        width: 8; height: 8; radius: 4
        x: ss.pad + index * ss.step - 4
        anchors.verticalCenter: parent.verticalCenter
        color: index <= ss.value ? root.fg : root.faint
      }
    }
    Rectangle {
      width: 46; height: 46; radius: 23
      x: ss.pad + ss.value * ss.step - 23
      color: root.surface2
      border.width: 1
      border.color: root.faint
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Text { anchors.centerIn: parent; text: ss.glyph; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 18 }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function setFrom(px) {
        var v = Math.round((px - ss.pad) / Math.max(ss.step, 1))
        v = Math.max(0, Math.min(ss.stops.length - 1, v))
        if (v !== ss.value) ss.moved(v)
      }
      onPressed: (m) => setFrom(m.x)
      onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
    }
  }

  // Settings row: label + explanation on the left, a switch on the right.
  component Toggle: Rectangle {
    id: tg
    property string label
    property string detail
    property bool checked
    signal toggled
    Layout.fillWidth: true
    implicitHeight: tgCol.implicitHeight + 24
    radius: 16
    color: tgMouse.containsMouse && enabled ? root.surface2 : root.surface
    opacity: enabled ? 1 : 0.45
    ColumnLayout {
      id: tgCol
      anchors { left: parent.left; right: knobTrack.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 12 }
      spacing: 3
      Text { Layout.fillWidth: true; text: tg.label; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 14 }
      Text { Layout.fillWidth: true; text: tg.detail; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.dim; font.family: root.font; font.pixelSize: 11 }
    }
    Rectangle {
      id: knobTrack
      anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
      width: 42; height: 24; radius: 12
      color: tg.checked ? root.accent : root.faint
      Rectangle {
        width: 18; height: 18; radius: 9
        y: 3
        x: tg.checked ? parent.width - width - 3 : 3
        color: tg.checked ? root.bg : root.fg
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea { id: tgMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (tg.enabled) tg.toggled() }
  }

  component SectionLabel: RowLayout {
    property string label
    property string value
    Layout.fillWidth: true
    Text { text: parent.label; textFormat: Text.PlainText; color: root.dim; font.family: root.font; font.pixelSize: 14 }
    Item { Layout.fillWidth: true }
    Text { text: parent.value; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 14 }
  }

  // Edge zone of the tone row: shown only when chips are hidden on that side.
  // Hovering scrolls toward it (for a plain mouse); clicking jumps ~a page.
  component Edge: Item {
    id: edge
    property int dir: 1
    required property var ts
    readonly property Flickable fl: ts.flick
    anchors { top: parent.top; bottom: parent.bottom }
    width: 40
    visible: dir < 0 ? edge.fl.contentX > 1 : edge.fl.contentX < edge.ts.maxX - 1
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: edge.dir < 0 ? root.bg : Qt.alpha(root.bg, 0) }
        GradientStop { position: 0.55; color: root.bg }
        GradientStop { position: 1; color: edge.dir < 0 ? Qt.alpha(root.bg, 0) : root.bg }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      x: edge.dir < 0 ? 4 : parent.width - width - 4
      text: edge.dir < 0 ? "\u2039" : "\u203a"
      font.pixelSize: 20
      color: hov.hovered ? root.accent : root.dim
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: edge.ts.page(edge.dir) }
    Timer {
      id: tick
      interval: 16; repeat: true
      running: hov.hovered && edge.visible
      property real speed: 3
      onRunningChanged: speed = 3
      onTriggered: { speed = Math.min(9, speed + 0.15); edge.ts.nudge(edge.dir * speed) }
    }
  }

  // One horizontally scrolling row of tone chips (wheel, swipe, drag, or
  // hover/click the ‹ › edges); the active chip scrolls into view.
  component ToneScroller: Item {
    id: ts
    property string activeKey
    signal chosen(string key)
    Layout.fillWidth: true
    implicitHeight: 46                       // 4px above/below the chips for key-hint badges
    clip: true
    readonly property real maxX: Math.max(0, fl.contentWidth - fl.width)
    readonly property Flickable flick: fl
    Flickable {
      id: fl
      anchors.fill: parent
      contentWidth: tsRow.implicitWidth
      contentHeight: height
      flickableDirection: Flickable.HorizontalFlick
      boundsBehavior: Flickable.StopAtBounds
      Row {
        id: tsRow
        y: 4
        spacing: 8
        Repeater {
          id: tsRep
          model: root.modeTones
          Chip {
            required property var modelData
            required property int index
            hint: index < 8 ? String(index + 1) : ""
            label: root.styleLabel(modelData.key)
            active: ts.activeKey === modelData.key
            onClicked: ts.chosen(modelData.key)
          }
        }
      }
    }
    WheelHandler {
      onWheel: (e) => {
        var d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x
        scrollAnim.stop()
        fl.contentX = Math.max(0, Math.min(ts.maxX, fl.contentX - d))
      }
    }
    NumberAnimation { id: scrollAnim; target: fl; property: "contentX"; duration: 180; easing.type: Easing.OutCubic }
    function ensureVisible() {
      for (var i = 0; i < root.modeTones.length; i++) {
        if (root.modeTones[i].key !== activeKey) continue
        var it = tsRep.itemAt(i)
        if (!it) return
        var x = fl.contentX
        if (it.x < fl.contentX + 24) x = it.x - 24
        else if (it.x + it.width > fl.contentX + fl.width - 24) x = it.x + it.width - fl.width + 24
        x = Math.max(0, Math.min(maxX, x))
        if (x !== fl.contentX) { scrollAnim.to = x; scrollAnim.restart() }
        return
      }
    }
    onActiveKeyChanged: Qt.callLater(ensureVisible)
    onWidthChanged: Qt.callLater(ensureVisible)
    // Edge zones: hovering scrolls toward that edge (mouse/touchpad without
    // horizontal swipe); clicking jumps by most of a page.
    function nudge(dx) {
      scrollAnim.stop()
      fl.contentX = Math.max(0, Math.min(ts.maxX, fl.contentX + dx))
    }
    function page(dir) {
      scrollAnim.to = Math.max(0, Math.min(ts.maxX, fl.contentX + dir * fl.width * 0.7))
      scrollAnim.restart()
    }
    Edge { ts: ts; dir: -1; anchors.left: parent.left }
    Edge { ts: ts; dir: 1; anchors.right: parent.right }
  }

  // ---- window -------------------------------------------------------------
  PanelWindow {
    id: win
    screen: {
      var want = Quickshell.env("POLISH_MONITOR")
      var list = Quickshell.screens
      for (var i = 0; i < list.length; i++) if (list[i].name === want) return list[i]
      return list[0]
    }
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "text-polish"

    Rectangle {
      anchors.fill: parent
      color: "#000000"
      opacity: 0.35
      MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    Rectangle {
      id: card
      width: Math.min(600, parent.width - 32)
      height: (root.view === "main" ? col.implicitHeight : root.view === "adjust" ? adjustCol.implicitHeight : settingsCol.implicitHeight) + 40
      anchors.centerIn: parent
      radius: 22
      color: root.bg
      border.width: 1
      border.color: root.faint
      MouseArea { anchors.fill: parent; onClicked: { root.agentMenu = false; root.blurText() } }   // swallow clicks so the scrim doesn't close

      opacity: 0; scale: 0.97
      Component.onCompleted: { opacity = 1; scale = 1 }
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      Item { id: focusSink; focus: true }
      // Alt press/release bubbles up here from whichever control has focus.
      Keys.onPressed: (e) => { if (e.key === Qt.Key_Alt || e.key === Qt.Key_AltGr) root.altDown() }
      Keys.onReleased: (e) => { if (e.key === Qt.Key_Alt || e.key === Qt.Key_AltGr) root.altUp() }
      readonly property bool typing: editor.activeFocus || originalView.activeFocus || adjustNote.activeFocus || intentField.activeFocus || refineField.activeFocus
      Shortcut { sequence: "Escape"; onActivated: root.view === "adjust" ? root.closeAdjust() : root.view === "settings" ? root.view = "main" : root.refineOpen ? root.closeRefine() : Qt.quit() }
      Shortcut { sequence: "/"; enabled: root.view === "main" && !card.typing; onActivated: root.openRefine() }
      Shortcut { sequence: "Alt+D"; enabled: root.view === "main"; onActivated: root.toggleDiff() }
      Shortcut { sequences: ["Ctrl+,", "Alt+S"]; onActivated: root.openSettings() }
      Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; onActivated: root.view === "adjust" ? root.generateAdjusted() : root.mode === "reply" ? root.copyAndClose() : (root.mode === "rewrite" && root.editable ? root.apply("replace") : root.copy()) }
      Shortcut { sequences: ["Ctrl+Shift+Return", "Ctrl+Shift+Enter"]; enabled: root.view === "main" && root.mode !== "read" && (root.editable || root.mode === "reply"); onActivated: root.apply(root.mode === "reply" ? "paste" : "insert") }
      Shortcut { sequence: "Alt+M"; enabled: root.view === "main"; onActivated: root.cycleMode() }
      Shortcut { sequence: "Ctrl+R"; enabled: root.view === "main"; onActivated: root.regenerate(false) }
      Shortcut { sequence: "Ctrl+Shift+R"; enabled: root.view === "main"; onActivated: root.regenerate(true) }
      // Left/Right page through versions unless a text box has the cursor; Alt+Left/Right always do.
      Shortcut { sequence: "Left"; enabled: root.view === "main" && !card.typing; onActivated: root.go(-1) }
      Shortcut { sequence: "Right"; enabled: root.view === "main" && !card.typing; onActivated: root.go(1) }
      Shortcut { sequence: "Alt+Left"; enabled: root.view === "main"; onActivated: root.go(-1) }
      Shortcut { sequence: "Alt+Right"; enabled: root.view === "main"; onActivated: root.go(1) }
      Shortcut { sequence: "Alt+1"; onActivated: root.toneByIndex(0) }
      Shortcut { sequence: "Alt+2"; onActivated: root.toneByIndex(1) }
      Shortcut { sequence: "Alt+3"; onActivated: root.toneByIndex(2) }
      Shortcut { sequence: "Alt+4"; onActivated: root.toneByIndex(3) }
      Shortcut { sequence: "Alt+5"; onActivated: root.toneByIndex(4) }
      Shortcut { sequence: "Alt+6"; onActivated: root.toneByIndex(5) }
      Shortcut { sequence: "Alt+7"; onActivated: root.toneByIndex(6) }
      Shortcut { sequence: "Alt+8"; onActivated: root.toneByIndex(7) }
      Shortcut { sequence: "Alt+A"; onActivated: root.cycleAgent() }
      Shortcut { sequence: "Alt+O"; enabled: root.view === "main"; onActivated: root.toggleOriginal() }
      Shortcut { sequence: "Alt+J"; enabled: root.view === "main"; onActivated: root.openAdjust() }

      // ================= main view =================
      ColumnLayout {
        id: col
        visible: root.view === "main"
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
        spacing: 16

        // Header
        Item {
          id: header
          Layout.fillWidth: true
          implicitHeight: 38

          Rectangle {
            id: agentPill
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.min(pillRow.implicitWidth + 24, (header.width - seg.width) / 2 - 10)
            clip: true
            height: 34
            radius: 17
            color: pillMouse.containsMouse || root.agentMenu ? root.surface2 : root.surface
            visible: root.agents.length > 0
            Row {
              id: pillRow
              anchors.centerIn: parent
              spacing: 6
              Text { text: "\u{F06A9}"; textFormat: Text.PlainText; color: root.accent; font.family: root.font; font.pixelSize: 14 }
              Text { text: root.agentLabel; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 13 }
              Text { text: "\u{F0140}"; textFormat: Text.PlainText; color: root.dim; font.family: root.font; font.pixelSize: 13 }
            }
            MouseArea { id: pillMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); root.agentMenu = !root.agentMenu } }
          }

          KeyHint { k: "A"; visible: agentPill.visible && opacity > 0; anchors.top: agentPill.top; anchors.right: agentPill.right }

          // Rewrite | Reply | Read switch (Alt+M cycles)
          Rectangle {
            id: seg
            anchors.centerIn: parent
            width: segRow.implicitWidth + 8
            height: 38
            radius: 19
            color: root.surface
            KeyHint { k: "M" }
            Row {
              id: segRow
              anchors.centerIn: parent
              spacing: 4
              Repeater {
                model: root.modes
                Rectangle {
                  required property var modelData
                  width: segText.implicitWidth + 28
                  height: 30
                  radius: 15
                  color: root.mode === modelData.key ? root.fg : (segMouse.containsMouse ? root.surface2 : "transparent")
                  Text {
                    id: segText
                    anchors.centerIn: parent
                    text: modelData.label
                    textFormat: Text.PlainText
                    color: root.mode === modelData.key ? root.bg : root.fg
                    font.family: root.font; font.pixelSize: 14
                    font.weight: root.mode === modelData.key ? Font.DemiBold : Font.Normal
                  }
                  MouseArea { id: segMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); root.setMode(modelData.key) } }
                }
              }
            }
          }
          IconButton { id: closeBtn; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F0156}"; onClicked: Qt.quit() }
          IconButton { anchors.right: closeBtn.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F0493}"; hint: "S"; onClicked: root.openSettings() }
        }

        // Reply mode: what you want to say (Enter drafts the reply)
        Rectangle {
          visible: root.mode === "reply"
          Layout.fillWidth: true
          implicitHeight: 44
          radius: 22
          color: root.surface
          border.width: intentField.activeFocus ? 1 : 0
          border.color: root.accent
          RowLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 6 }
            spacing: 8
            TextField {
              id: intentField
              Layout.fillWidth: true
              text: root.intent
              onTextEdited: root.intent = text
              placeholderText: "What do you want to say? e.g. yes, but Monday works better"
              placeholderTextColor: root.faint
              color: root.fg
              selectionColor: root.surface2
              font.family: root.font
              font.pixelSize: 14
              background: null
              onAccepted: root.draftReply()
            }
            Rectangle {
              implicitWidth: 34; implicitHeight: 34; radius: 17
              color: draftMouse.containsMouse ? root.surface2 : "transparent"
              Text { anchors.centerIn: parent; text: "\u{F048A}"; textFormat: Text.PlainText; color: root.accent; font.family: root.font; font.pixelSize: 16 }
              MouseArea { id: draftMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.draftReply() }
            }
          }
        }

        // Refine: one-off instruction for the version on screen (/ opens, Enter applies, Esc closes)
        Rectangle {
          visible: root.refineOpen
          Layout.fillWidth: true
          implicitHeight: 44
          radius: 22
          color: root.surface
          border.width: 1
          border.color: refineField.activeFocus ? root.accent : root.faint
          RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 6 }
            spacing: 6
            Text { text: "\u{F03EB}"; textFormat: Text.PlainText; color: root.accent; font.family: root.font; font.pixelSize: 15 }
            TextField {
              id: refineField
              Layout.fillWidth: true
              placeholderText: root.pinnedFlash !== "" ? root.pinnedFlash
                             : root.mode === "read" ? "Refine: e.g. focus on the deadlines \u00b7 Enter"
                             : "Refine: e.g. address it to Priya, make it shorter \u00b7 Enter"
              placeholderTextColor: root.pinnedFlash !== "" ? root.accent : root.faint
              color: root.fg
              selectionColor: root.surface2
              font.family: root.font
              font.pixelSize: 14
              background: null
              onAccepted: root.refine(text)
            }
            Rectangle {
              visible: refineField.text.trim() !== ""
              implicitWidth: 32; implicitHeight: 32; radius: 16
              color: refPinMouse.containsMouse ? root.surface2 : "transparent"
              Text { anchors.centerIn: parent; text: "\u{F0403}"; textFormat: Text.PlainText; color: root.dim; font.family: root.font; font.pixelSize: 15 }
              MouseArea {
                id: refPinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.pinRefine()
                ToolTip.visible: containsMouse; ToolTip.delay: 400
                ToolTip.text: "Pin: use this every time for " + root.styleLabel(root.style)
              }
            }
            Rectangle {
              implicitWidth: 32; implicitHeight: 32; radius: 16
              color: refGoMouse.containsMouse ? root.surface2 : "transparent"
              Text { anchors.centerIn: parent; text: "\u{F048A}"; textFormat: Text.PlainText; color: root.accent; font.family: root.font; font.pixelSize: 15 }
              MouseArea { id: refGoMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refine(refineField.text) }
            }
          }
        }

        // Result box
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: boxCol.implicitHeight + 28
          radius: 18
          color: "transparent"
          border.width: 1
          border.color: root.faint

          ColumnLayout {
            id: boxCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            Item {
              Layout.fillWidth: true
              // Sized for whichever is taller, so toggling the original never resizes the popup.
              Layout.preferredHeight: Math.min(Math.max(editor.implicitHeight, originalView.implicitHeight, root.showDiff ? diffView.implicitHeight : 0, 96), 320)
              ScrollView {
                anchors.fill: parent
                visible: !root.showOriginal && !root.showDiff
                clip: true
                TextArea {
                  id: editor
                  readOnly: !root.current || root.current.busy || !root.current.ok
                  textFormat: TextEdit.PlainText
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  color: root.current && !root.current.busy && !root.current.ok ? root.danger : root.fg
                  selectionColor: root.surface2
                  selectedTextColor: root.fg
                  font.family: root.font
                  font.pixelSize: 16
                  padding: 4
                  background: null
                  // Keep hand edits with their version so paging away and back preserves them.
                  onTextChanged: {
                    var v = root.at()
                    if (!root.loadingEditor && v && !v.busy && v.ok && v.text !== text) {
                      v.text = text
                      if (!v.edited) { v.edited = true; root.versions = root.versions.slice() }  // refresh footer tag
                    }
                  }
                }
              }
              Text {
                visible: root.busy && !root.showOriginal && editor.length === 0
                anchors { left: parent.left; top: parent.top; margins: 4 }
                text: root.busyVerb() + " with " + (root.current ? root.current.agentLabel : root.agentLabel) + "…  "
                      + root.fmtSecs(Math.max(0, root.now - (root.current ? root.current.startedAt : root.now)))
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.font
                font.pixelSize: 16
                SequentialAnimation on opacity {
                  running: root.busy; loops: Animation.Infinite
                  NumberAnimation { from: 1; to: 0.35; duration: 700 }
                  NumberAnimation { from: 0.35; to: 1; duration: 700 }
                }
              }
              // Changes view: read-only; click it to go back to editing.
              ScrollView {
                anchors.fill: parent
                visible: root.showDiff && !root.showOriginal
                clip: true
                TextArea {
                  id: diffView
                  text: root.diff.html
                  readOnly: true
                  textFormat: TextEdit.RichText
                  wrapMode: TextEdit.Wrap
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: 16
                  padding: 4
                  background: null
                  HoverHandler { cursorShape: Qt.IBeamCursor }
                  TapHandler { onTapped: { root.showDiff = false; editor.forceActiveFocus() } }
                }
              }
              ScrollView {
                anchors.fill: parent
                visible: root.showOriginal
                clip: true
                TextArea {
                  id: originalView
                  text: root.original
                  readOnly: true
                  textFormat: TextEdit.PlainText
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  color: root.dim
                  selectionColor: root.surface2
                  selectedTextColor: root.fg
                  font.family: root.font
                  font.pixelSize: 16
                  padding: 4
                  background: null
                }
              }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.faint }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8
              IconButton { glyph: root.copied ? "\u{F012C}" : "\u{F018F}"; enabled: !root.showOriginal && !root.busy && root.current.ok; onClicked: root.copy() }
              Text {
                // X/Twitter limit; JS length counts emoji as 2, close to X's own weighting.
                visible: root.current && root.current.style === "tweet" && !root.showOriginal && !root.busy && root.current.ok
                text: editor.length + " / 280"
                textFormat: Text.PlainText
                color: editor.length > 280 ? root.danger : root.dim
                font.family: root.font; font.pixelSize: 13
              }
              Text {
                visible: root.showDiff && !root.showOriginal && !root.copied
                text: root.diff.count === 0 ? "No changes needed" : root.diff.count + (root.diff.count === 1 ? " change" : " changes")
                textFormat: Text.PlainText
                color: root.dim; font.family: root.font; font.pixelSize: 13
              }
              Text {
                text: root.copied ? "Copied" : ""
                textFormat: Text.PlainText
                color: root.dim; font.family: root.font; font.pixelSize: 13
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                visible: root.diffAvailable
                implicitWidth: diffText.implicitWidth + 24
                implicitHeight: 34
                radius: 17
                color: root.showDiff ? Qt.alpha(root.accent, 0.16) : (diffMouse.containsMouse ? root.surface2 : root.surface)
                border.width: root.showDiff ? 1 : 0
                border.color: root.accent
                Text {
                  id: diffText
                  anchors.centerIn: parent
                  text: "Changes"
                  textFormat: Text.PlainText
                  color: root.showDiff ? root.accent : root.fg
                  font.family: root.font; font.pixelSize: 13
                }
                KeyHint { k: "D" }
                MouseArea { id: diffMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); root.toggleDiff() } }
              }
              Rectangle {
                implicitWidth: origText.implicitWidth + 24
                implicitHeight: 34
                radius: 17
                color: root.showOriginal ? Qt.alpha(root.accent, 0.16) : (origMouse.containsMouse ? root.surface2 : root.surface)
                border.width: root.showOriginal ? 1 : 0
                border.color: root.accent
                Text {
                  id: origText
                  anchors.centerIn: parent
                  text: root.showOriginal ? (root.mode === "rewrite" ? "Rewrite" : root.mode === "reply" ? "Reply" : "Result") : "Original"
                  textFormat: Text.PlainText
                  color: root.showOriginal ? root.accent : root.fg
                  font.family: root.font; font.pixelSize: 13
                }
                KeyHint { k: "O" }
                MouseArea { id: origMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); root.toggleOriginal() } }
              }
              // Version pager: < n / N >
              Rectangle {
                visible: root.versions.length > 1
                implicitWidth: pager.implicitWidth + 8
                implicitHeight: 34
                radius: 17
                color: root.surface
                Row {
                  id: pager
                  anchors.centerIn: parent
                  spacing: 2
                  Rectangle {
                    width: 30; height: 30; radius: 15
                    color: prevMouse.containsMouse && root.vi > 0 ? root.surface2 : "transparent"
                    Text { anchors.centerIn: parent; text: "\u{F0141}"; textFormat: Text.PlainText; font.family: root.font; font.pixelSize: 16; color: root.vi > 0 ? root.fg : root.faint }
                    MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); root.go(-1) } }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(implicitWidth, 44)
                    horizontalAlignment: Text.AlignHCenter
                    text: (root.vi + 1) + " / " + root.versions.length
                    textFormat: Text.PlainText
                    color: root.fg; font.family: root.font; font.pixelSize: 13
                  }
                  Rectangle {
                    width: 30; height: 30; radius: 15
                    color: nextMouse.containsMouse && root.vi < root.versions.length - 1 ? root.surface2 : "transparent"
                    Text { anchors.centerIn: parent; text: "\u{F0142}"; textFormat: Text.PlainText; font.family: root.font; font.pixelSize: 16; color: root.vi < root.versions.length - 1 ? root.fg : root.faint }
                    MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.blurText(); root.go(1) } }
                  }
                }
              }
              IconButton {
                glyph: "\u{F03EB}"; enabled: !root.busy && root.current.ok
                onClicked: root.refineOpen ? root.closeRefine() : root.openRefine()
                ToolTip.visible: refHover.hovered; ToolTip.delay: 400; ToolTip.text: "Refine this version (/)"
                HoverHandler { id: refHover }
              }
              IconButton { glyph: "\u{F0450}"; enabled: !root.busy; onClicked: (mods) => root.regenerate(mods & Qt.ShiftModifier) }
            }
          }
        }

        // Adjust (pinned) + one scrolling row of tones
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Chip { label: "Adjust"; glyph: "\u{F062E}"; hint: "J"; onClicked: root.openAdjust() }
          Rectangle { implicitWidth: 1; implicitHeight: 26; color: root.faint }
          ToneScroller { activeKey: root.style; onChosen: (k) => root.pick(k) }
        }

        // Actions
        RowLayout {
          Layout.fillWidth: true
          spacing: 12
          // Rewrite: Insert / Replace (Close / Copy for read-only text).
          // Reply: Paste at your cursor / Copy and close, to paste into the chat yourself.
          // Read: Close / Copy (stays open so you can keep reading).
          readonly property bool writes: root.mode === "reply" || (root.mode === "rewrite" && root.editable)
          ActionButton {
            label: root.mode === "reply" ? "Paste" : (parent.writes ? "Insert" : "Close")
            enabled: parent.writes ? (!root.busy && root.current.ok) : true
            onClicked: root.mode === "reply" ? root.apply("paste") : (parent.writes ? root.apply("insert") : Qt.quit())
          }
          ActionButton {
            label: root.mode === "reply" ? "Copy" : (parent.writes ? "Replace" : "Copy")
            primary: true
            enabled: !root.busy && root.current.ok
            onClicked: root.mode === "reply" ? root.copyAndClose() : (parent.writes ? root.apply("replace") : root.copy())
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: {
              var v = root.current
              var head = !v ? "Starting\u2026"
                       : v.busy ? "Generating with " + v.agentLabel
                       : (v.ok ? "Generated by " : "Failed with ") + v.agentLabel + " in " + root.fmtSecs(v.ms)
              return v ? head + " \u00b7 " + root.versionTags(v) : head
            }
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.dim
            font.family: root.font
            font.pixelSize: 11
          }
          Text {
            text: "\u{F02D7}"
            textFormat: Text.PlainText
            color: keysHover.hovered ? root.fg : root.faint
            font.family: root.font
            font.pixelSize: 14
            HoverHandler { id: keysHover }
            ToolTip {
              visible: keysHover.hovered
              delay: 150
              contentItem: Text {
                text: "Esc close \u00b7 Ctrl+Enter " + (root.editable ? "replace" : "copy") + " \u00b7 Ctrl+Shift+Enter insert\n"
                    + "\u2190/\u2192 versions \u00b7 Ctrl+R regenerate (Shift+\u21BB or Ctrl+Shift+R: from original) \u00b7 Alt+1\u20138 tone\n"
                    + "/ refine \u00b7 Hold Alt to see keys \u00b7 Alt+M rewrite/reply/read \u00b7 Alt+J adjust \u00b7 Alt+A agent \u00b7 Alt+O original \u00b7 Alt+D changes \u00b7 Alt+S settings"
                textFormat: Text.PlainText
                color: root.fg
                font.family: root.font
                font.pixelSize: 12
                lineHeight: 1.3
              }
              background: Rectangle { color: root.surface; radius: 10; border.width: 1; border.color: root.faint }
            }
          }
        }
      }

      // ================= adjust view =================
      ColumnLayout {
        id: adjustCol
        visible: root.view === "adjust"
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
        spacing: 14

        Item {
          Layout.fillWidth: true
          implicitHeight: 38
          Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Cancel"
            textFormat: Text.PlainText
            color: cancelMouse.containsMouse ? root.fg : root.dim
            font.family: root.font; font.pixelSize: 15
            MouseArea { id: cancelMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeAdjust() }
          }
          Text {
            anchors.centerIn: parent
            text: "Adjust"
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.font; font.pixelSize: 20; font.weight: Font.DemiBold
          }
        }

        SectionLabel { label: "Tone"; value: "" }
        ToneScroller { activeKey: root.adjStyle; onChosen: (k) => root.switchAdjustTone(k) }

        SectionLabel { Layout.topMargin: 6; label: "Length"; value: root.lengthStops[root.adjLength] + (root.adjLength === 1 ? " (tone default)" : "") }
        StepSlider { stops: root.lengthStops; value: root.adjLength; glyph: "T"; onMoved: (v) => root.adjLength = v }

        SectionLabel { visible: root.mode !== "read"; Layout.topMargin: 6; label: "Emoji"; value: root.emojiStops[root.adjEmoji] }
        StepSlider { visible: root.mode !== "read"; stops: root.emojiStops; value: root.adjEmoji; glyph: "\u{F01F5}"; onMoved: (v) => root.adjEmoji = v }

        // Pinned instructions for this tone: pin icon = on/off, words = edit.
        Flow {
          Layout.fillWidth: true
          Layout.topMargin: 6
          spacing: 8
          visible: root.pinsFor(root.adjStyle).length > 0
          Repeater {
            model: root.pinsFor(root.adjStyle)
            Rectangle {
              id: pc
              required property var modelData
              required property int index
              readonly property bool editing: root.editingPin === index
              width: Math.min(pcRow.implicitWidth + 20, 260)
              height: 32
              radius: 16
              color: editing ? Qt.alpha(root.accent, 0.16) : root.surface
              border.width: editing || modelData.on ? 1 : 0
              border.color: editing ? root.accent : Qt.alpha(root.accent, 0.5)
              Row {
                id: pcRow
                anchors.verticalCenter: parent.verticalCenter
                x: 6
                spacing: 4
                Rectangle {
                  width: 24; height: 24; radius: 12
                  anchors.verticalCenter: parent.verticalCenter
                  color: pinTog.containsMouse ? root.surface2 : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: pc.modelData.on ? "\u{F0403}" : "\u{F0404}"
                    textFormat: Text.PlainText
                    color: pc.modelData.on ? root.accent : root.faint
                    font.family: root.font; font.pixelSize: 14
                  }
                  MouseArea {
                    id: pinTog; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePin(root.adjStyle, pc.index)
                    ToolTip.visible: containsMouse; ToolTip.delay: 400
                    ToolTip.text: pc.modelData.on ? "On: used every time. Click to pause." : "Paused. Click to use it again."
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, 200)
                  elide: Text.ElideRight
                  text: root.pinPreview(pc.modelData.text)
                  textFormat: Text.PlainText
                  color: pc.modelData.on || pc.editing ? root.fg : root.dim
                  font.family: root.font; font.pixelSize: 13
                  font.strikeout: false
                  MouseArea {
                    anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                    onClicked: root.editPin(pc.index)
                  }
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: 6
          implicitHeight: 110
          radius: 18
          color: root.surface
          border.width: adjustNote.activeFocus || root.editingPin >= 0 ? 1 : 0
          border.color: root.accent
          // Corner controls: pin the text (one-time box), or delete/done while editing a pin.
          Row {
            z: 2
            anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
            spacing: 4
            Text {
              visible: root.editingPin >= 0
              anchors.verticalCenter: parent.verticalCenter
              text: "Editing pin  "
              textFormat: Text.PlainText
              color: root.accent; font.family: root.font; font.pixelSize: 11
            }
            IconButton {
              visible: root.editingPin >= 0
              width: 30; height: 30
              glyph: "\u{F01B4}"
              onClicked: root.deleteEditingPin()
            }
            IconButton {
              visible: root.editingPin >= 0
              width: 30; height: 30
              glyph: "\u{F012C}"
              onClicked: root.stopEditingPin()
            }
            IconButton {
              visible: root.editingPin < 0 && adjustNote.text.trim() !== ""
              enabled: root.pinsFor(root.adjStyle).length < root.maxPins
              width: 30; height: 30
              glyph: "\u{F0403}"
              onClicked: root.pinBoxText()
              ToolTip.visible: pinHover.hovered; ToolTip.delay: 400
              ToolTip.text: enabled ? "Pin: use this every time for " + root.styleLabel(root.adjStyle) : "Up to " + root.maxPins + " pins per tone"
              HoverHandler { id: pinHover }
            }
          }
          ScrollView {
            anchors.fill: parent
            anchors.margins: 10
            anchors.bottomMargin: 40
            clip: true
            TextArea {
              id: adjustNote
              placeholderText: root.mode === "read" ? "Just this time: what should it focus on? (e.g. just the deadlines) \u2014 pin it to keep it"
                                                    : "Just this time: e.g. address it to Priya, mention the demo \u2014 pin it to keep it"
              placeholderTextColor: root.faint
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              color: root.fg
              selectionColor: root.surface2
              font.family: root.font
              font.pixelSize: 14
              background: null
            }
          }
        }

        ActionButton {
          Layout.topMargin: 4
          label: "Generate"
          primary: true
          onClicked: root.generateAdjusted()
        }

        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: "Adds a new version \u00b7 pinned instructions apply every time; the box is one-time"
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.font
          font.pixelSize: 11
        }
      }

      // ================= settings view =================
      ColumnLayout {
        id: settingsCol
        visible: root.view === "settings"
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
        spacing: 14

        Item {
          Layout.fillWidth: true
          implicitHeight: 38
          Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Done"
            textFormat: Text.PlainText
            color: doneMouse.containsMouse ? root.fg : root.dim
            font.family: root.font; font.pixelSize: 15
            MouseArea { id: doneMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.view = "main" }
          }
          Text {
            anchors.centerIn: parent
            text: "Settings"
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.font; font.pixelSize: 20; font.weight: Font.DemiBold
          }
        }

        SectionLabel { label: "Tone chips"; value: root.tones.length + " of " + root.styles.length + " shown" }
        // Tap a chip to show/hide it; drag it to change the row order.
        Item {
          id: orderArea
          Layout.fillWidth: true
          implicitHeight: orderFlow.implicitHeight
          property int dragFrom: -1
          property int dragTo: -1
          property point dragPos
          property string dragLabel
          function slotAt(p) {
            var n = orderRep.count, last = -1, first = orderRep.itemAt(0)
            for (var i = 0; i < n; i++) {
              var it = orderRep.itemAt(i)
              if (p.y < it.y - 4 || p.y >= it.y + it.height + 4) continue
              if (p.x < it.x + it.width / 2) return i
              last = i
            }
            if (last >= 0) return last + 1
            return first && p.y < first.y ? 0 : n
          }
          function begin(i, label) { dragFrom = i; dragLabel = label; dragTo = i }
          function move(p) { dragPos = p; dragTo = slotAt(p) }
          function end() {
            var f = dragFrom, t = dragTo
            dragFrom = -1; dragTo = -1
            if (f >= 0 && t >= 0) root.moveTone(f, t)
          }
          Flow {
            id: orderFlow
            width: parent.width
            spacing: 8
            Repeater {
              id: orderRep
              model: root.orderedStyles
              Chip {
                id: oc
                required property var modelData
                required property int index
                label: modelData.label
                glyph: active ? "\u{F012C}" : "\u{F0415}"
                active: root.setting("tones").indexOf(modelData.key) >= 0
                opacity: orderArea.dragFrom === index ? 0.3 : 1
                onClicked: root.toggleTone(modelData.key)
                DragHandler {
                  target: null
                  cursorShape: Qt.ClosedHandCursor
                  onActiveChanged: active ? orderArea.begin(oc.index, oc.label) : orderArea.end()
                  onTranslationChanged: if (active) orderArea.move(oc.mapToItem(orderArea, centroid.position))
                }
              }
            }
          }
          // Where the chip will land.
          Rectangle {
            readonly property Item ref: orderArea.dragTo < 0 ? null
                : orderRep.itemAt(Math.min(orderArea.dragTo, orderRep.count - 1))
            readonly property bool after: orderArea.dragTo >= orderRep.count
            visible: orderArea.dragFrom >= 0 && ref !== null
                     && orderArea.dragTo !== orderArea.dragFrom && orderArea.dragTo !== orderArea.dragFrom + 1
            width: 3; radius: 1.5
            height: ref ? ref.height : 0
            x: ref ? (after ? ref.x + ref.width + 2.5 : ref.x - 5.5) : 0
            y: ref ? ref.y : 0
            color: root.accent
          }
          // The chip under your cursor while dragging.
          Rectangle {
            visible: orderArea.dragFrom >= 0
            z: 30
            x: orderArea.dragPos.x - width / 2
            y: orderArea.dragPos.y - height / 2
            width: ghostText.implicitWidth + 32; height: 38; radius: 19
            color: root.surface2
            border.width: 1.5; border.color: root.accent
            opacity: 0.92
            Text { id: ghostText; anchors.centerIn: parent; text: orderArea.dragLabel; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 14 }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: "Tap to show or hide \u00b7 drag to reorder. Alt+1\u20138 follow the shown chips; hidden tones still work from the browser menu and apps.conf."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.dim; font.family: root.font; font.pixelSize: 11
          }
          Text {
            text: "Reset"
            textFormat: Text.PlainText
            color: resetMouse.containsMouse ? root.fg : root.dim
            font.family: root.font; font.pixelSize: 12; font.underline: resetMouse.containsMouse
            MouseArea { id: resetMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resetTones() }
          }
        }

        SectionLabel { Layout.topMargin: 6; label: "Features"; value: "" }
        Toggle {
          label: "Show changes"
          detail: "A Changes button (Alt+D) that highlights what the AI removed and added."
          checked: root.setting("showChanges")
          onToggled: root.setSetting("showChanges", !checked)
        }
        Toggle {
          label: "Open Proofread on changes"
          detail: "Proofread results start in the Changes view, so you can check them at a glance."
          enabled: root.setting("showChanges")
          checked: root.setting("autoChanges")
          onToggled: root.setSetting("autoChanges", !checked)
        }
        Toggle {
          label: "Prepare next tone"
          detail: "Writes the next chip's version in the background, so switching to it is instant. Uses one extra agent run each time."
          checked: root.setting("prefetch")
          onToggled: root.setSetting("prefetch", !checked)
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 4
          horizontalAlignment: Text.AlignHCenter
          text: "Saved automatically \u00b7 Esc to go back"
          textFormat: Text.PlainText
          color: root.dim; font.family: root.font; font.pixelSize: 11
        }
      }

      // Agent dropdown (above the content)
      Rectangle {
        visible: root.agentMenu && root.view === "main"
        z: 10
        x: 20
        y: 20 + header.height + 6
        width: Math.max(200, menuCol.implicitWidth + 12)
        height: menuCol.implicitHeight + 12
        radius: 14
        color: root.bg
        border.width: 1
        border.color: root.faint
        Column {
          id: menuCol
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
          Repeater {
            model: root.agents
            Rectangle {
              required property var modelData
              width: menuCol.width
              height: 36
              radius: 10
              color: rowMouse.containsMouse ? root.surface2 : "transparent"
              Row {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 10
                Text {
                  width: 16
                  text: modelData.id === root.agent ? "\u{F012C}" : ""
                  textFormat: Text.PlainText; color: root.accent; font.family: root.font; font.pixelSize: 14
                }
                Text { text: modelData.label; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 14 }
              }
              MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setAgent(modelData.id) }
            }
          }
        }
      }
    }
  }
}
