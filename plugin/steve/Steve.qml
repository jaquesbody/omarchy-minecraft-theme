import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property bool opened: false
  function open(payload) {
    opened = true
    try {
      var p = typeof payload === "string" && payload ? JSON.parse(payload) : (payload || {})
      if (p && p.x !== undefined) anchorX = Number(p.x) || anchorX
      if (p && p.y !== undefined) anchorY = Number(p.y) || anchorY
    } catch (e) {}
  }
  function close() { opened = false }

  property int guiScale: 2
  // Base units from left; anchorY is negative offset up from bottom edge.
  property int anchorX: 8
  property int anchorY: -80
  property bool blinking: false
  property int bobPhase: 0

  Timer {
    id: blinkTimer
    interval: 3200
    repeat: true
    running: root.opened
    onTriggered: {
      root.blinking = true
      blinkOff.start()
    }
  }
  Timer {
    id: blinkOff
    interval: 140
    onTriggered: root.blinking = false
  }
  Timer {
    interval: 1200
    repeat: true
    running: root.opened
    onTriggered: root.bobPhase = (root.bobPhase + 1) % 2
  }

  onBlinkingChanged: steveCanvas.requestPaint()
  onBobPhaseChanged: steveCanvas.requestPaint()

  function paintGrid(ctx, ox, oy, s, rows, cmap) {
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r]
      for (var c = 0; c < row.length; c++) {
        var col = cmap[row[c]]
        if (!col) continue
        ctx.fillStyle = col
        ctx.fillRect(ox + c * s, oy + r * s, s, s)
      }
    }
  }

  // Original 14×20 blocky companion (not a Mojang asset). All rows length 14.
  // Clearer face: hair fringe, eye whites + blue irises, nose, smile.
  readonly property var gridOpen: [
    "....hhhhhh....",
    "...hhhhhhhh...",
    "..hhhhhhhhhh..",
    "..hhsssssshh..",
    ".hssssssssssh.",
    ".hsEEssssEEsh.",
    ".hsiiEsiEiish.",
    ".hssssssssssh.",
    ".hsssnnnnsssh.",
    ".hssssMMssssh.",
    ".hssssssssssh.",
    ".bbssssssssbb.",
    ".bbMMMMMMMMbb.",
    ".bbMMMMMMMMbb.",
    ".bbMMMMMMMMbb.",
    ".bbMMMMMMMMbb.",
    "..bAAAAAAAAb..",
    "..pppppppppp..",
    "..pppppppppp..",
    "..pppppppppp.."
  ]

  readonly property var gridBlink: [
    "....hhhhhh....",
    "...hhhhhhhh...",
    "..hhhhhhhhhh..",
    "..hhsssssshh..",
    ".hssssssssssh.",
    ".hssssssssssh.",
    ".hsEEEEEEEEsh.",
    ".hssssssssssh.",
    ".hsssnnnnsssh.",
    ".hssssMMssssh.",
    ".hssssssssssh.",
    ".bbssssssssbb.",
    ".bbMMMMMMMMbb.",
    ".bbMMMMMMMMbb.",
    ".bbMMMMMMMMbb.",
    ".bbMMMMMMMMbb.",
    "..bAAAAAAAAb..",
    "..pppppppppp..",
    "..pppppppppp..",
    "..pppppppppp.."
  ]

  readonly property var steveMap: {
    "h": "#c8a27a",
    "s": "#d4b08a",
    "E": "#ffffff",
    "i": "#3b5dc9",
    "n": "#c4956a",
    "M": "#3dafd0",
    "A": "#2f9fc4",
    "b": "#c8a27a",
    "p": "#4a3fa0",
    ".": "#00000000"
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "minecraft-steve"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: steveArea }

    readonly property int s: root.guiScale
    readonly property int steveW: 14 * s
    readonly property int steveH: 20 * s

    // Full-size coordinate space (PanelWindow content may not report height early)
    Item {
      id: screen
      anchors.fill: parent

      Item {
        id: steveArea
        width: panel.steveW
        height: panel.steveH
        x: root.anchorX * panel.s
        y: screen.height - height - Math.max(0, -root.anchorY) * panel.s + root.bobPhase * panel.s

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: Quickshell.execDetached([
            "omarchy-shell", "shell", "summon",
            "io.github.jaquesbody.minecraft-inventory", "{}"
          ])
        }

        Canvas {
          id: steveCanvas
          anchors.fill: parent
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Component.onCompleted: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return
            var s = panel.s
            var rows = root.blinking ? root.gridBlink : root.gridOpen
            root.paintGrid(ctx, 0, 0, s, rows, root.steveMap)
          }
        }
      }
    }
  }
}
