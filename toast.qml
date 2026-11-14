// Polish undo toast: a small bar at the bottom of the screen after Replace,
// Insert or Paste. Shown by apply.sh (quickshell -p toast.qml), independent of
// desktop notifications, so it also shows with Do Not Disturb on. Takes no
// keyboard focus. Undo runs `apply.sh undo`; it closes itself after 10s
// (paused while the mouse is over it).
// Env: POLISH_TOAST_MSG, POLISH_DIR, POLISH_MONITOR.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root
  readonly property string msg: Quickshell.env("POLISH_TOAST_MSG") || "Replaced"
  readonly property string dir: Quickshell.env("POLISH_DIR") || ""
  readonly property int lifetime: 10000
  property real left: lifetime

  property var theme: ({})
  function c(name, fallback) { return theme[name] || fallback }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    blockLoading: true
    onLoaded: {
      var t = {}, re = /^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm, m, s = text()
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
  readonly property string font: "JetBrainsMono Nerd Font"

  Timer {
    interval: 50; repeat: true; running: !hover.hovered
    onTriggered: { root.left -= interval; if (root.left <= 0) Qt.quit() }
  }
  function undo() {
    Quickshell.execDetached([dir + "/apply.sh", "undo"])
    Qt.quit()
  }

  PanelWindow {
    screen: {
      var want = Quickshell.env("POLISH_MONITOR"), list = Quickshell.screens
      for (var i = 0; i < list.length; i++) if (list[i].name === want) return list[i]
      return list[0]
    }
    anchors.bottom: true
    margins.bottom: 96                  // clear of the dock
    implicitWidth: bar.width
    implicitHeight: bar.height
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "text-polish-toast"

    Rectangle {
      id: bar
      width: row.implicitWidth + 28
      height: 52
      radius: 26
      color: root.bg
      border.width: 1
      border.color: root.faint
      clip: true
      opacity: 0
      Component.onCompleted: opacity = 1
      Behavior on opacity { NumberAnimation { duration: 140 } }
      HoverHandler { id: hover }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F012C}"
          color: root.accent; font.family: root.font; font.pixelSize: 15
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.msg
          textFormat: Text.PlainText
          color: root.fg; font.family: root.font; font.pixelSize: 14
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: undoText.implicitWidth + 28; height: 34; radius: 17
          color: undoMouse.containsMouse ? Qt.lighter(root.fg, 1.08) : root.fg
          Text {
            id: undoText
            anchors.centerIn: parent
            text: "Undo"
            color: root.bg; font.family: root.font; font.pixelSize: 14; font.weight: Font.DemiBold
          }
          MouseArea { id: undoMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.undo() }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Super+Alt+Z"
          color: root.faint; font.family: root.font; font.pixelSize: 11
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 26; height: 26; radius: 13
          color: closeMouse.containsMouse ? root.surface2 : "transparent"
          Text { anchors.centerIn: parent; text: "\u{F0156}"; color: root.dim; font.family: root.font; font.pixelSize: 14 }
          MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.quit() }
        }
      }
      // Time left
      Rectangle {
        anchors { left: parent.left; bottom: parent.bottom }
        height: 2
        width: parent.width * Math.max(0, root.left / root.lifetime)
        color: root.accent
        opacity: 0.6
      }
    }
  }
}
