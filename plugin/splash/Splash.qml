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
  property string splashText: ""
  property int autoHideMs: 3500

  // Original splash lines — no Mojang copy.
  readonly property var lines: [
    "100% original pixels!",
    "Now with more Steve!",
    "Blocks all the way down!",
    "Creepers? Not here.",
    "Press SUPER+M!",
    "Made for Omarchy!",
    "Diamonds are optional!",
    "Hand-crafted, no assets!",
    "Villager-approved!",
    "RGB not included.",
    "Try the inventory!",
    "Double the hearts!",
    "Hunger bar says hi!",
    "Obsidian chic.",
    "Monocraft forever!",
    "Idle CPU: zero!",
    "Respawn anytime.",
    "XP for your desktop!",
    "Splash text: original.",
    "Click Steve for loot."
  ]

  function pickLine() {
    return lines[Math.floor(Math.random() * lines.length)]
  }

  function open(payload) {
    try {
      var p = typeof payload === "string" && payload ? JSON.parse(payload) : (payload || {})
      if (p.text) splashText = String(p.text)
      else splashText = pickLine()
      if (p.ms !== undefined) autoHideMs = Math.max(500, Number(p.ms) || 3500)
    } catch (e) {
      splashText = pickLine()
    }
    opened = true
    autoHide.restart()
    pop.restart()
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

  // Scale pop-in like the title-screen splash
  property real popScale: 0.6
  NumberAnimation {
    id: pop
    target: root
    property: "popScale"
    from: 0.55
    to: 1.0
    duration: 180
    easing.type: Easing.OutBack
  }

  PanelWindow {
    id: panel
    visible: root.opened && !root.screensaverActive
    // Full-width strip under the bar; visual centers itself inside.
    // PanelWindow only supports edge anchors (no x / horizontalCenter).
    anchors { top: true; left: true; right: true }
    implicitHeight: 120
    margins { top: 48 }
    color: "transparent"
    WlrLayershell.namespace: "minecraft-splash"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Input only on the text itself; rest of the strip stays click-through
    mask: Region { item: textHit }

    Item {
      id: visual
      anchors.fill: parent
      scale: root.popScale
      opacity: root.opened ? 1 : 0

      Text {
        id: splashLabel
        anchors.centerIn: parent
        text: root.splashText
        color: "#ffff55"
        font.family: "Monocraft"
        font.pixelSize: 20
        font.bold: true
        style: Text.Raised
        styleColor: "#3f3f00"
        // Classic splash tilt
        rotation: -18
        scale: 1.15
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        width: Math.min(parent.width - 8, 480)
      }

      // Click the splash to dismiss
      Item {
        id: textHit
        width: Math.min(420, splashLabel.width + 40)
        height: 56
        anchors.centerIn: parent

        MouseArea {
          anchors.fill: parent
          onClicked: root.close()
        }
      }
    }
  }
}
