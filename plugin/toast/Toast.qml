import QtQuick
import Quickshell
import Quickshell.Wayland

import Quickshell.Hyprland
Item {
  id: root

  property bool opened: false

  // Hide this panel while Omarchy screensaver (org.omarchy.screensaver) is up.
  property bool screensaverActive: false
  property var ssAddrs: ({})
  function ssSet(address, on) {
    var next = {}
    var n = 0
    var addr = String(address || "")
    for (var k in root.ssAddrs) {
      if (k !== addr && root.ssAddrs[k]) { next[k] = true; n++ }
    }
    if (on && addr) { next[addr] = true; n++ }
    root.ssAddrs = next
    root.screensaverActive = n > 0
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name === "openwindow") {
        var open = String(event && event.data ? event.data : "").split(",")
        try { if (event.parse) open = event.parse(4) } catch (e) {}
        if (String(open[2] || "") === "org.omarchy.screensaver")
          root.ssSet(String(open[0] || ""), true)
      } else if (name === "closewindow") {
        var close = String(event && event.data ? event.data : "").split(",")
        try { if (event.parse) close = event.parse(1) } catch (e) {}
        root.ssSet(String(close[0] || ""), false)
      }
    }
  }
  Process {
    id: ssProbe
    running: false
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onTextChanged: {
        try {
          var cs = JSON.parse(text)
          for (var i = 0; i < cs.length; i++) {
            if (String(cs[i].class || "") === "org.omarchy.screensaver")
              root.ssSet(String(cs[i].address || "probe"), true)
          }
        } catch (e) {}
      }
    }
  }
  Component.onCompleted: ssProbe.running = true
  property string titleText: "Advancement Made!"
  property string subtitleText: "Original work"
  property string kind: "advancement"
  property int autoHideMs: 4500

  function open(payload) {
    try {
      var p = typeof payload === "string" && payload ? JSON.parse(payload) : (payload || {})
      if (p.title) titleText = String(p.title)
      if (p.subtitle) subtitleText = String(p.subtitle)
      if (p.kind) kind = String(p.kind)
      if (p.ms !== undefined) autoHideMs = Math.max(500, Number(p.ms) || 4500)
    } catch (e) {}
    opened = true
    slideIn.restart()
    autoHide.restart()
    Quickshell.execDetached([
      "pw-play", Quickshell.env("HOME") + "/.local/share/minecraft-theme/sounds/toast.wav"
    ])
  }

  function close() {
    opened = false
    autoHide.stop()
  }

  Timer {
    id: autoHide
    interval: root.autoHideMs
    onTriggered: root.close()
  }

  // Slide-in offset (px); animates from off-screen right to parked position
  property real slideFrom: 0
  NumberAnimation {
    id: slideIn
    target: root
    property: "slideFrom"
    from: 280
    to: 0
    duration: 220
    easing.type: Easing.OutCubic
  }

  PanelWindow {
    id: panel
    visible: root.opened && !root.screensaverActive
    anchors { top: true; right: true }
    // Park under the bar; leave room so toast never covers clock controls
    implicitWidth: 320
    implicitHeight: 64
    margins { top: 48; right: 12 }
    color: "transparent"
    WlrLayershell.namespace: "minecraft-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Input only on the toast card itself
    mask: Region { item: card }

    readonly property int s: 2

    Item {
      id: hitRoot
      anchors.fill: parent

      Item {
        id: card
        x: root.slideFrom
        y: 0
        width: parent.width
        height: parent.height

        // MC toast chrome: dark slate with light bevel (original colors)
        Rectangle {
          anchors.fill: parent
          color: "#242424"
          border.color: "#5c5c5c"
          border.width: 2
          radius: 0
        }
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 2
          color: "#8c8c8c"
        }
        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 2
          color: "#8c8c8c"
        }
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 2
          color: "#101010"
        }
        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 2
          color: "#101010"
        }

        // Icon well (original tiny badge, not a Mojang item)
        Rectangle {
          id: iconWell
          x: 10
          y: Math.round((parent.height - 36) / 2)
          width: 36
          height: 36
          color: "#3a3a3a"
          border.color: "#1a1a1a"
          border.width: 2

          Canvas {
            anchors.fill: parent
            anchors.margins: 4
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              // Simple original "medallion": gold ring + green check block
              var w = width, h = height
              ctx.fillStyle = "#c9a227"
              ctx.fillRect(0, 0, w, 3)
              ctx.fillRect(0, h - 3, w, 3)
              ctx.fillRect(0, 0, 3, h)
              ctx.fillRect(w - 3, 0, 3, h)
              ctx.fillStyle = "#55ff55"
              // checkmark pixels
              var px = Math.max(2, Math.floor(w / 14))
              var cells = [[3, 8], [4, 9], [5, 10], [6, 9], [7, 8], [8, 7], [9, 6], [10, 5]]
              for (var i = 0; i < cells.length; i++) {
                ctx.fillRect(cells[i][0] * px, cells[i][1] * px, px, px)
              }
            }
            Component.onCompleted: requestPaint()
          }
        }

        Text {
          anchors.left: iconWell.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: root.titleText + "\n" + root.subtitleText
          color: "#ffffff"
          font.family: "Monocraft"
          font.pixelSize: 13
          font.bold: true
          lineHeight: 1.25
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.WrapAnywhere
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.close()
        }
      }
    }
  }
}
