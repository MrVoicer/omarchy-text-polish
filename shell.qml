// Polish — AI rewrite popup for selected text (standalone Quickshell config).
// Launched by ./polish; env: POLISH_INPUT, POLISH_STYLE, POLISH_EDITABLE,
// POLISH_WINDOW, POLISH_MONITOR, POLISH_DIR.
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

  property string style: Quickshell.env("POLISH_STYLE") || "proofread"
  property var results: ({})     // style -> { ok, text }
  property var tokens: ({})      // style -> latest request token
  property int nextToken: 1
  property var startedAt: ({})   // style -> ms timestamp of the latest request
  property real now: Date.now()
  Timer { interval: 100; repeat: true; running: root.busy; onTriggered: root.now = Date.now() }
  function fmtSecs(ms) { return (ms / 1000).toFixed(1) + "s" }
  property bool showOriginal: false
  property bool copied: false

  // ---- agent picker -------------------------------------------------------
  property var agents: []          // [{ id, label }] installed + supported
  property string agent: ""        // "" until the list loads; rewrite.sh then picks
  property bool agentMenu: false
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/text-polish/agent"
  readonly property string agentLabel: {
    for (var i = 0; i < agents.length; i++) if (agents[i].id === agent) return agents[i].label
    return agent || "Agent"
  }

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
        root.request(root.style)
      }
    }
  }

  function setAgent(id) {
    agentMenu = false
    if (id === agent) return
    agent = id
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "sh", statePath, id])
    tokens = ({})                  // drop in-flight answers from the old agent
    results = ({})
    copied = false
    request(style)
  }

  function cycleAgent() {
    if (agents.length < 2) return
    var i = 0
    for (; i < agents.length; i++) if (agents[i].id === agent) break
    setAgent(agents[(i + 1) % agents.length].id)
  }

  readonly property var current: results[style]
  readonly property bool busy: current === undefined
  readonly property string original: inputFile.text()

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
      property string jobStyle
      property int token
      environment: root.agent ? ({ POLISH_AGENT: root.agent }) : ({})
      stdout: StdioCollector {
        onStreamFinished: { root.jobDone(job.jobStyle, job.token, text); job.destroy() }
      }
    }
  }

  function request(s) {
    var t = nextToken++
    var tk = Object.assign({}, tokens); tk[s] = t; tokens = tk
    var st = Object.assign({}, startedAt); st[s] = Date.now(); startedAt = st
    now = Date.now()
    var r = Object.assign({}, results); delete r[s]; results = r
    var j = jobComp.createObject(root, { jobStyle: s, token: t,
      command: [dir + "/rewrite.sh", s, inputPath] })
    j.running = true
  }

  function jobDone(s, t, out) {
    if (tokens[s] !== t) return               // superseded by a regenerate
    var nl = out.indexOf("\n")
    var head = nl < 0 ? out : out.slice(0, nl)
    var body = nl < 0 ? "" : out.slice(nl + 1)
    var r = Object.assign({}, results)
    var ms = Date.now() - (startedAt[s] || Date.now())
    r[s] = head.indexOf("OK ") === 0 ? { ok: true, text: body, ms: ms }
                                      : { ok: false, text: body.trim() || "Rewrite failed.", ms: ms }
    results = r
  }

  function pick(s) {
    style = s
    copied = false
    if (results[s] === undefined && tokens[s] === undefined) request(s)
  }

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

  // ---- UI -----------------------------------------------------------------
  component Chip: Rectangle {
    id: chip
    property string label
    property bool active
    signal clicked
    implicitWidth: chipText.implicitWidth + 32
    implicitHeight: 38
    radius: 19
    color: active ? Qt.alpha(root.accent, 0.16) : (chipMouse.containsMouse ? root.surface2 : root.surface)
    border.width: active ? 1.5 : 0
    border.color: root.accent
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      textFormat: Text.PlainText
      color: chip.active ? root.accent : root.fg
      font.family: root.font
      font.pixelSize: 14
    }
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
  }

  component IconButton: Rectangle {
    id: ib
    property string glyph
    property string tip
    signal clicked
    width: 38; height: 38; radius: 19
    color: ibMouse.containsMouse ? root.surface2 : root.surface
    opacity: enabled ? 1 : 0.4
    Text { anchors.centerIn: parent; text: ib.glyph; textFormat: Text.PlainText; color: root.fg; font.family: root.font; font.pixelSize: 16 }
    MouseArea { id: ibMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
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
    MouseArea { id: abMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.clicked() }
  }

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
      height: col.implicitHeight + 40
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

      Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
      Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; onActivated: root.editable ? root.apply("replace") : root.copy() }
      Shortcut { sequences: ["Ctrl+Shift+Return", "Ctrl+Shift+Enter"]; enabled: root.editable; onActivated: root.apply("insert") }
      Shortcut { sequence: "Ctrl+R"; onActivated: root.request(root.style) }
      Shortcut { sequence: "Alt+1"; onActivated: root.pick("proofread") }
      Shortcut { sequence: "Alt+2"; onActivated: root.pick("casual") }
      Shortcut { sequence: "Alt+3"; onActivated: root.pick("punchy") }
      Shortcut { sequence: "Alt+4"; onActivated: root.pick("concise") }
      Shortcut { sequence: "Alt+5"; onActivated: root.pick("formal") }
      Shortcut { sequence: "Alt+6"; onActivated: root.pick("tweet") }
      Shortcut { sequence: "Alt+A"; onActivated: root.cycleAgent() }

      ColumnLayout {
        id: col
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
          IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "󰅖"; onClicked: Qt.quit() }
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

            Text {
              Layout.fillWidth: true
              visible: root.showOriginal
              text: root.original
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              maximumLineCount: 6
              elide: Text.ElideRight
              color: root.dim
              font.family: root.font
              font.pixelSize: 13
              font.italic: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.faint; visible: root.showOriginal }

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(Math.max(editor.implicitHeight, 96), 320)
              ScrollView {
                anchors.fill: parent
                clip: true
                TextArea {
                  id: editor
                  readonly property string source: root.busy ? "" : root.current.text
                  onSourceChanged: text = source
                  readOnly: !root.current || !root.current.ok
                  textFormat: TextEdit.PlainText
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  color: root.current && !root.current.ok ? root.danger : root.fg
                  selectionColor: root.surface2
                  selectedTextColor: root.fg
                  font.family: root.font
                  font.pixelSize: 16
                  padding: 4
                  background: null
                  Keys.onEscapePressed: Qt.quit()
                }
              }
              Text {
                visible: root.busy
                anchors { left: parent.left; top: parent.top; margins: 4 }
                text: "Rewriting with " + root.agentLabel + "\u2026  " + root.fmtSecs(Math.max(0, root.now - (root.startedAt[root.style] || root.now)))
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
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.faint }

            RowLayout {
              Layout.fillWidth: true
              IconButton { glyph: root.copied ? "󰄬" : "󰆏"; enabled: !root.busy && root.current.ok; onClicked: root.copy() }
              Text {
                // X/Twitter limit; JS length counts emoji as 2, close to X's own weighting.
                visible: root.style === "tweet" && !root.busy && root.current.ok
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
              Text {
                text: root.showOriginal ? "Hide original" : "Show original"
                textFormat: Text.PlainText
                color: origMouse.containsMouse ? root.fg : root.dim
                font.family: root.font; font.pixelSize: 13
                MouseArea { id: origMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showOriginal = !root.showOriginal }
              }
              Item { width: 8 }
              IconButton { glyph: "󰑐"; enabled: !root.busy; onClicked: root.request(root.style) }
            }
          }
        }

        // Style chips
        Flow {
          Layout.fillWidth: true
          spacing: 8
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
          text: (root.busy ? "Generating with " + root.agentLabel
                           : (root.current.ok ? "Generated by " : "Failed with ") + root.agentLabel + " in " + root.fmtSecs(root.current.ms))
                + " · review before using · Esc close · Ctrl+Enter " + (root.editable ? "replace" : "copy") + " · Alt+1–6 style · Alt+A agent"
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.font
          font.pixelSize: 11
        }
      }

      // Agent dropdown (above the content)
      Rectangle {
        visible: root.agentMenu
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
