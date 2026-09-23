import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
  id: root

  property bool opened: false
  property int clickCount: 0
  // Herobrine easter egg: after 10 clicks the idle Steve turns eerie for a few seconds.
  property bool herobrine: false
  onHerobrineChanged: {
    steveFallback.requestPaint()
    if (herobrine) herobrineTimer.restart()
  }

  function open(payload) {
    opened = true
    cursorTimer.start()
    pollCursor()
  }
  function close() {
    opened = false
    cursorTimer.stop()
    herobrine = false
    herobrineTimer.stop()
  }
  // IPC probe for toggle scripts (FLAG files desync across shell restarts).
  function status() { return opened ? "open" : "closed" }

  // Stationary Steve with big white eyes + evil grin + white glow.
  function onSteveClick() {
    clickCount++
    if (clickCount >= 10 && !herobrine) {
      clickCount = 0
      herobrine = true
      animPlay = false
      Quickshell.execDetached([
        Quickshell.env("HOME") + "/.local/bin/minecraft-toast",
        "Herobrine",
        "He is watching."
      ])
    }
  }
  Timer {
    id: herobrineTimer
    interval: 5000
    onTriggered: root.herobrine = false
  }

  property int guiScale: 3
  property int anchorX: 0
  property int anchorY: 14
  property int cursorX: 0
  property int cursorY: 0
  property bool blinking: false
  // Play the walk-cycle only while the mouse has moved recently.
  property bool animPlay: false
  property int lastAnimX: -1
  property int lastAnimY: -1

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
          var nx = Number(parts[0]) || 0
          var ny = Number(parts[1]) || 0
          root.cursorX = nx
          root.cursorY = ny
          if (nx !== root.lastAnimX || ny !== root.lastAnimY) {
            root.lastAnimX = nx
            root.lastAnimY = ny
            root.animPlay = true
            animIdle.restart()
          }
        }
      }
    }
  }

  Timer {
    id: animIdle
    interval: 700
    onTriggered: root.animPlay = false
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
  // Optional clip: drop steve.gif (ping-pong walk, green removed) into the
  // plugin dir. Plays only while the mouse cursor is moving.
  property bool hasVideo: false
  FileView {
    id: videoProbe
    path: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.jaquesbody.minecraft-steve/steve.gif"
    preload: true
    printErrors: false
    onLoaded: root.hasVideo = data().length > 0
    onLoadFailed: root.hasVideo = false
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
    readonly property int textH: 14 * s

    Item {
      id: screen
      anchors.fill: parent

      Item {
        id: steveArea
        width: Math.max(panel.steveW, 160 * panel.s / 2)
        height: panel.steveH + panel.textH + 6 * panel.s
        x: root.anchorX * panel.s
        y: root.anchorY * panel.s

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            root.onSteveClick()
            Quickshell.execDetached([
              "omarchy-shell", "shell", "summon",
              "io.github.jaquesbody.minecraft-inventory", "{}"
            ])
          }
        }

        // Unmirrored: source frames face/walk toward the right.
        Item {
          id: steveFlip
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: panel.steveW
          height: panel.steveH

          // Ping-pong walk cycle (green screen removed). Plays only while
          // the cursor moves; freezes on frame 0 when idle. Hidden for Herobrine.
          AnimatedImage {
            id: steveAnim
            anchors.fill: parent
            source: Qt.resolvedUrl("steve.gif")
            sourceSize: Qt.size(panel.steveW, panel.steveH)
            visible: !root.herobrine && status === AnimatedImage.Ready
            playing: root.opened && root.animPlay && !root.herobrine
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
            asynchronous: false
            onStatusChanged: {
              if (status === AnimatedImage.Ready)
                root.hasVideo = true
            }
            onPlayingChanged: {
              if (!playing) {
                // Restart from the first frame next time the mouse moves.
                try { steveAnim.currentFrame = 0 } catch (e) {}
              }
            }
          }

          Image {
            id: steveImg
            anchors.fill: parent
            source: Qt.resolvedUrl("steve.png")
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(48, 59)
            smooth: false
            mipmap: false
            asynchronous: false
            visible: !root.herobrine && steveAnim.status !== AnimatedImage.Ready && status === Image.Ready
          }

          // White glow behind Herobrine (drawn under the figure).
          Rectangle {
            id: herobrineGlow
            visible: root.herobrine
            anchors.fill: parent
            anchors.margins: -6 * panel.s
            color: "#40ffffff"
            radius: 4 * panel.s
            z: -1
          }
          Rectangle {
            id: herobrineGlow2
            visible: root.herobrine
            anchors.fill: parent
            anchors.margins: -2 * panel.s
            color: "#a0ffffff"
            radius: 2 * panel.s
            z: -1
          }

          Canvas {
            id: steveFallback
            anchors.fill: parent
            visible: root.herobrine || (steveAnim.status !== AnimatedImage.Ready && steveImg.status !== Image.Ready)
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              if (width <= 0 || height <= 0) return
              var s = Math.max(1, Math.floor(width / 14))
              if (root.herobrine) {
                root.paintGrid(ctx, 0, 0, s, root.gridHerobrine, root.steveMap)
              } else {
                var rows = root.blinking ? root.gridBlink : root.gridOpen
                root.paintGrid(ctx, 0, 0, s, rows, root.steveMap)
              }
            }
          }
        }

        Text {
          id: posLabel
          anchors.top: steveFlip.bottom
          anchors.topMargin: 3 * panel.s
          anchors.horizontalCenter: parent.horizontalCenter
          horizontalAlignment: Text.AlignHCenter
          text: "Position " + root.cursorX + ", " + root.cursorY
          color: "#ffffff"
          style: Text.Outline
          styleColor: "#000000"
          font { family: "Monocraft"; pixelSize: 4 * panel.s }
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

  // Herobrine: same body as idle Steve, but giant white eyes + evil grin.
  readonly property var gridHerobrine: [
    "....hhhhhh....",
    "...hhhhhhhh...",
    "..hhhhhhhhhh..",
    "..hhsssssshh..",
    ".hssssssssssh.",
    ".hsEEEEEEEEsh.",
    ".hsEEEEEEEEsh.",
    ".hssssssssssh.",
    ".hsssnnnnsssh.",
    ".hsMMssssMMsh.",
    ".hsssMMMMMssh.",
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
    "M": "#8ecff0",
    "A": "#5a9ec9",
    "b": "#c8a27a",
    "p": "#4a3fa0",
    ".": "#00000000"
  }
}
