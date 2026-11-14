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
    { key: "casual", label: "Casual" },
    { key: "punchy", label: "Punchy" },
    { key: "concise", label: "Concise" },
    { key: "formal", label: "Formal" },
    { key: "tweet", label: "Tweet" }
  ]
  function styleLabel(k) {
    for (var i = 0; i < styles.length; i++) if (styles[i].key === k) return styles[i].label
    return k
  }

  readonly property var lengthStops: ["Short", "Moderate", "Long"]          // Moderate = the tone's own length
  readonly property var lengthArgs: ["short", "", "long"]
  readonly property var emojiStops: ["None", "Few", "Moderate", "Lots"]
  readonly property var emojiArgs: ["none", "few", "moderate", "lots"]

  // ---- versions -----------------------------------------------------------
  // Each: { id, style, agent, agentLabel, length, emoji, note, busy, ok, text, ms, startedAt }
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
  property bool copied: false
  property string view: "main"              // "main" | "adjust"
  readonly property string original: inputFile.text()

  // Adjust panel state, remembered per tone: style -> { length, emoji, note }
  property var adjustByStyle: ({})
  property string adjStyle: style
  property int adjLength: 1
  property int adjEmoji: 0
  function adjustFor(s) { return adjustByStyle[s] || { length: 1, emoji: 0, note: "" } }

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
    var c = current
    generate(c ? c.style : style, c ? { length: c.length, emoji: c.emoji, note: c.note } : {})
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
      stdout: StdioCollector {
        onStreamFinished: { root.jobDone(job.versionId, text); job.destroy() }
      }
    }
  }

  // opts: { length: "short"|"long"|"", emoji: "none"|"few"|"moderate"|"lots"|"", note: string }
  function generate(s, opts) {
    var v = {
      id: nextId++, style: s, agent: agent, agentLabel: agentLabel,
      length: opts.length || "", emoji: opts.emoji || "", note: (opts.note || "").trim(),
      busy: true, ok: false, text: "", ms: 0, startedAt: Date.now()
    }
    versions = versions.concat([v])
    style = s
    showOriginal = false
    copied = false
    now = Date.now()
    vi = versions.length - 1
    var env = { POLISH_LENGTH: v.length, POLISH_EMOJI: v.emoji, POLISH_NOTE: v.note }
    if (agent) env.POLISH_AGENT = agent
    var j = jobComp.createObject(root, { versionId: v.id, environment: env,
      command: [dir + "/rewrite.sh", s, inputPath] })
    j.running = true
  }

  function jobDone(id, out) {
    var nl = out.indexOf("\n")
    var head = nl < 0 ? out : out.slice(0, nl)
    var body = nl < 0 ? "" : out.slice(nl + 1)
    var list = versions.slice()
    for (var i = 0; i < list.length; i++) {
      if (list[i].id !== id) continue
      var v = Object.assign({}, list[i])
      v.busy = false
      v.ms = Date.now() - v.startedAt
      v.ok = head.indexOf("OK ") === 0
      v.text = v.ok ? body : (body.trim() || "Rewrite failed.")
      list[i] = v
      versions = list
      if (i === vi) showVersion()
      return
    }
  }

  // Load the on-screen version into the editor (its text may have been edited).
  property bool loadingEditor: false
  // Read versions[vi] directly: inside onViChanged the `current` binding may not have updated yet.
  function at() { return vi >= 0 && vi < versions.length ? versions[vi] : null }
  function showVersion() {
    var v = at()
    loadingEditor = true
    editor.text = v && !v.busy ? v.text : ""
    loadingEditor = false
    copied = false
  }
  onViChanged: { var v = at(); if (v) style = v.style; showVersion() }

  function go(delta) {
    var n = vi + delta
    if (n < 0 || n >= versions.length) return
    showOriginal = false
    vi = n
  }

  // Chip: jump to the latest version of that tone, or generate one.
  function pick(s) {
    showOriginal = false
    for (var i = versions.length - 1; i >= 0; i--) {
      if (versions[i].style === s) { vi = i; style = s; return }
    }
    generate(s, {})
  }

  function regenerate() {
    var c = current
    generate(c ? c.style : style, c ? { length: c.length, emoji: c.emoji, note: c.note } : {})
  }

  // ---- adjust panel -------------------------------------------------------
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
    saveAdjust()
    loadAdjust(s)
  }
  function generateAdjusted() {
    saveAdjust()
    view = "main"
    generate(adjStyle, { length: lengthArgs[adjLength], emoji: emojiArgs[adjEmoji], note: adjustNote.text })
  }

  function versionTags(v) {
    if (!v) return ""
    var t = [styleLabel(v.style)]
    if (v.length) t.push(v.length === "short" ? "short" : "long")
    if (v.emoji) t.push(v.emoji === "none" ? "no emoji" : v.emoji + " emoji")
    if (v.note) t.push("“" + (v.note.length > 28 ? v.note.slice(0, 27) + "…" : v.note) + "”")
    return t.join(", ")
  }

  // ---- actions ------------------------------------------------------------
  function finalText() { return editor.text }

  function copy() {
    if (busy || !current.ok) return
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", finalText()])
    copied = true
    copiedTimer.restart()
  }

  function apply(mode) {
    if (busy || !current.ok) return
    Quickshell.execDetached([dir + "/apply.sh", mode, windowAddr, finalText()])
    Qt.quit()
  }

  Timer { id: copiedTimer; interval: 1400; onTriggered: root.copied = false }

  Component.onCompleted: agentList.running = true

  // ---- UI components ------------------------------------------------------
  component Chip: Rectangle {
    id: chip
    property string label
    property string glyph: ""
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
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
  }

  component IconButton: Rectangle {
    id: ib
    property string glyph
    signal clicked
    width: 38; height: 38; radius: 19
    color: ibMouse.containsMouse && ib.enabled ? root.surface2 : root.surface
    opacity: enabled ? 1 : 0.4
    Text { anchors.centerIn: parent; text: ib.glyph; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 16 }
    MouseArea { id: ibMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (ib.enabled) ib.clicked() }
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

  component SectionLabel: RowLayout {
    property string label
    property string value
    Layout.fillWidth: true
    Text { text: parent.label; textFormat: Text.PlainText; color: root.dim; font.family: root.font; font.pixelSize: 14 }
    Item { Layout.fillWidth: true }
    Text { text: parent.value; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 14 }
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
      height: (root.view === "main" ? col.implicitHeight : adjustCol.implicitHeight) + 40
      anchors.centerIn: parent
      radius: 22
      color: root.bg
      border.width: 1
      border.color: root.faint
      MouseArea { anchors.fill: parent; onClicked: root.agentMenu = false }   // swallow clicks so the scrim doesn't close

      opacity: 0; scale: 0.97
      Component.onCompleted: { opacity = 1; scale = 1 }
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      readonly property bool typing: editor.activeFocus || originalView.activeFocus || adjustNote.activeFocus
      Shortcut { sequence: "Escape"; onActivated: root.view === "adjust" ? root.view = "main" : Qt.quit() }
      Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; onActivated: root.view === "adjust" ? root.generateAdjusted() : (root.editable ? root.apply("replace") : root.copy()) }
      Shortcut { sequences: ["Ctrl+Shift+Return", "Ctrl+Shift+Enter"]; enabled: root.editable && root.view === "main"; onActivated: root.apply("insert") }
      Shortcut { sequence: "Ctrl+R"; enabled: root.view === "main"; onActivated: root.regenerate() }
      // Left/Right page through versions unless a text box has the cursor; Alt+Left/Right always do.
      Shortcut { sequence: "Left"; enabled: root.view === "main" && !card.typing; onActivated: root.go(-1) }
      Shortcut { sequence: "Right"; enabled: root.view === "main" && !card.typing; onActivated: root.go(1) }
      Shortcut { sequence: "Alt+Left"; enabled: root.view === "main"; onActivated: root.go(-1) }
      Shortcut { sequence: "Alt+Right"; enabled: root.view === "main"; onActivated: root.go(1) }
      Shortcut { sequence: "Alt+1"; onActivated: root.view === "adjust" ? root.switchAdjustTone("proofread") : root.pick("proofread") }
      Shortcut { sequence: "Alt+2"; onActivated: root.view === "adjust" ? root.switchAdjustTone("casual") : root.pick("casual") }
      Shortcut { sequence: "Alt+3"; onActivated: root.view === "adjust" ? root.switchAdjustTone("punchy") : root.pick("punchy") }
      Shortcut { sequence: "Alt+4"; onActivated: root.view === "adjust" ? root.switchAdjustTone("concise") : root.pick("concise") }
      Shortcut { sequence: "Alt+5"; onActivated: root.view === "adjust" ? root.switchAdjustTone("formal") : root.pick("formal") }
      Shortcut { sequence: "Alt+6"; onActivated: root.view === "adjust" ? root.switchAdjustTone("tweet") : root.pick("tweet") }
      Shortcut { sequence: "Alt+A"; onActivated: root.cycleAgent() }
      Shortcut { sequence: "Alt+O"; enabled: root.view === "main"; onActivated: root.showOriginal = !root.showOriginal }
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
            width: Math.min(pillRow.implicitWidth + 24, header.width / 2 - 70)
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
            MouseArea { id: pillMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.agentMenu = !root.agentMenu }
          }

          Text {
            anchors.centerIn: parent
            text: "Polish"
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.font
            font.pixelSize: 20
            font.weight: Font.DemiBold
          }
          IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F0156}"; onClicked: Qt.quit() }
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
              Layout.preferredHeight: Math.min(Math.max(editor.implicitHeight, originalView.implicitHeight, 96), 320)
              ScrollView {
                anchors.fill: parent
                visible: !root.showOriginal
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
                    if (!root.loadingEditor && v && !v.busy && v.ok) v.text = text
                  }
                }
              }
              Text {
                visible: root.busy && !root.showOriginal
                anchors { left: parent.left; top: parent.top; margins: 4 }
                text: "Rewriting with " + (root.current ? root.current.agentLabel : root.agentLabel) + "…  "
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
                text: root.copied ? "Copied" : ""
                textFormat: Text.PlainText
                color: root.dim; font.family: root.font; font.pixelSize: 13
              }
              Item { Layout.fillWidth: true }
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
                  text: root.showOriginal ? "Rewrite" : "Original"
                  textFormat: Text.PlainText
                  color: root.showOriginal ? root.accent : root.fg
                  font.family: root.font; font.pixelSize: 13
                }
                MouseArea { id: origMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showOriginal = !root.showOriginal }
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
                    MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.go(-1) }
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
                    MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.go(1) }
                  }
                }
              }
              IconButton { glyph: "\u{F0450}"; enabled: !root.busy; onClicked: root.regenerate() }
            }
          }
        }

        // Adjust + tone chips
        Flow {
          Layout.fillWidth: true
          spacing: 8
          Chip { label: "Adjust"; glyph: "\u{F062E}"; onClicked: root.openAdjust() }
          Rectangle { width: 1; height: 38; color: root.faint }
          Repeater {
            model: root.styles
            Chip {
              required property var modelData
              label: modelData.label
              active: root.style === modelData.key
              onClicked: root.pick(modelData.key)
            }
          }
        }

        // Actions
        RowLayout {
          Layout.fillWidth: true
          spacing: 12
          ActionButton {
            label: root.editable ? "Insert" : "Close"
            enabled: !root.editable || (!root.busy && root.current.ok)
            onClicked: root.editable ? root.apply("insert") : Qt.quit()
          }
          ActionButton {
            label: root.editable ? "Replace" : "Copy"
            primary: true
            enabled: !root.busy && root.current.ok
            onClicked: root.editable ? root.apply("replace") : root.copy()
          }
        }

        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: {
            var v = root.current
            var head = !v ? "Starting…"
                     : v.busy ? "Generating with " + v.agentLabel
                     : (v.ok ? "Generated by " : "Failed with ") + v.agentLabel + " in " + root.fmtSecs(v.ms)
            if (v) head += " · " + root.versionTags(v)
            return head + "\nEsc close · Ctrl+Enter " + (root.editable ? "replace" : "copy")
                 + " · ←/→ versions · Alt+1–6 tone · Alt+J adjust · Alt+A agent · Alt+O original"
          }
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.font
          font.pixelSize: 11
          lineHeight: 1.2
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
            MouseArea { id: cancelMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.saveAdjust(); root.view = "main" } }
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
        Flow {
          Layout.fillWidth: true
          spacing: 8
          Repeater {
            model: root.styles
            Chip {
              required property var modelData
              label: modelData.label
              active: root.adjStyle === modelData.key
              onClicked: root.switchAdjustTone(modelData.key)
            }
          }
        }

        SectionLabel { Layout.topMargin: 6; label: "Length"; value: root.lengthStops[root.adjLength] + (root.adjLength === 1 ? " (tone default)" : "") }
        StepSlider { stops: root.lengthStops; value: root.adjLength; glyph: "T"; onMoved: (v) => root.adjLength = v }

        SectionLabel { Layout.topMargin: 6; label: "Emoji"; value: root.emojiStops[root.adjEmoji] }
        StepSlider { stops: root.emojiStops; value: root.adjEmoji; glyph: "\u{F01F5}"; onMoved: (v) => root.adjEmoji = v }

        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: 6
          implicitHeight: 110
          radius: 18
          color: root.surface
          border.width: adjustNote.activeFocus ? 1 : 0
          border.color: root.accent
          ScrollView {
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            TextArea {
              id: adjustNote
              placeholderText: "Enter your adjustment request (e.g. address it to Priya, mention the demo)"
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
          text: "Adds a new version · settings are remembered per tone · Ctrl+Enter generate · Esc back"
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.font
          font.pixelSize: 11
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
