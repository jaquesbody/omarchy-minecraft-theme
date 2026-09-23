import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
  id: root

  property bool opened: false
  function open(payload) {
    opened = true
    cursorTimer.start()
    pollCursor()
  }
  function close() {
    opened = false
    cursorTimer.stop()
  }

  property int guiScale: 3
  property int anchorX: 8
  property int anchorY: 8
  property int cursorX: 0
  property int cursorY: 0
  property bool blinking: false
  property int bobPhase: 0

  Timer {
    id: cursorTimer
    interval: 250
    repeat: true
    running: root.opened
    onTriggered: root.pollCursor()
  }

  function pollCursor() {
    cursorProc.running = false
    cursorProc.running = true
  }

  Process {
    id: cursorProc
    running: false
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      onTextChanged: {
        var parts = text.trim().split(/[,\s]+/)
        if (parts.length >= 2) {
          root.cursorX = Number(parts[0]) || 0
          root.cursorY = Number(parts[1]) || 0
        }
      }
    }
  }

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
    readonly property int steveW: Math.floor(48 * s / 2)
    readonly property int steveH: Math.floor(59 * s / 2)
    readonly property int textH: 22 * s

    Item {
      id: screen
      anchors.fill: parent

      Item {
        id: steveArea
        width: Math.max(panel.steveW, 140 * panel.s / 2)
        height: panel.steveH + panel.textH + 6 * panel.s
        x: root.anchorX * panel.s
        y: root.anchorY * panel.s + root.bobPhase * panel.s

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: Quickshell.execDetached([
            "omarchy-shell", "shell", "summon",
            "io.github.jaquesbody.minecraft-inventory", "{}"
          ])
        }

        Image {
          id: steveImg
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: panel.steveW
          height: panel.steveH
          source: Qt.resolvedUrl("steve.png")
          fillMode: Image.PreserveAspectFit
          sourceSize: Qt.size(48, 59)
          smooth: false
          mipmap: false
          asynchronous: false
          visible: status === Image.Ready
        }

        Canvas {
          id: steveFallback
          anchors.fill: steveImg
          visible: steveImg.status !== Image.Ready
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Component.onCompleted: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return
            var s = Math.max(1, Math.floor(width / 14))
            var rows = root.blinking ? root.gridBlink : root.gridOpen
            root.paintGrid(ctx, 0, 0, s, rows, root.steveMap)
          }
        }

        Column {
          id: posCol
          anchors.top: steveImg.bottom
          anchors.topMargin: 4 * panel.s
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 1 * panel.s

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Position X, Y"
            color: "#ffffff"
            style: Text.Outline
            styleColor: "#000000"
            font { family: "Monocraft"; pixelSize: 7 * panel.s }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.cursorX + ", " + root.cursorY
            color: "#ffffff"
            style: Text.Outline
            styleColor: "#000000"
            font { family: "Monocraft"; pixelSize: 7 * panel.s }
          }
        }
      }
    }
  }

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
}
