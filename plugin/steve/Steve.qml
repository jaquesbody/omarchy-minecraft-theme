import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

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
  property int clickCount: 0
  // Herobrine: real Steve texture stays up; white eyes/smile/glow overlay on top.
  property bool herobrine: false
  onHerobrineChanged: {
    herobrineOverlay.requestPaint()
    if (herobrine) {
      animPlay = false
      try { steveAnim.currentFrame = 0 } catch (e) {}
      herobrineTimer.restart()
    }
  }

  function open(payload) {
    opened = true
    pollCursor()
  }
  function close() {
    opened = false
    herobrine = false
    herobrineTimer.stop()
  }
  function status() { return opened ? "open" : "closed" }

  // 10 clicks → stationary Herobrine for 5s (texture + white eyes/smile/glow).
  function onSteveClick() {
    clickCount++
    if (clickCount >= 10 && !herobrine) {
      clickCount = 0
      herobrine = true
      animPlay = false
      try { steveAnim.currentFrame = 0 } catch (e) {}
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
  property bool animPlay: false
  property int lastAnimX: -1
  property int lastAnimY: -1

  Timer {
    id: cursorTimer
    interval: 250
    repeat: true
    running: root.opened && !root.screensaverActive
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
            if (!root.herobrine) {
              root.animPlay = true
              animIdle.restart()
            }
          }
        }
      }
    }
  }

  Timer {
    id: animIdle
    interval: 700
    onTriggered: { if (!root.herobrine) root.animPlay = false }
  }

  Timer {
    id: blinkTimer
    interval: 3200
    repeat: true
    running: root.opened && !root.herobrine && !root.screensaverActive
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
    visible: root.opened && !root.screensaverActive
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

        Item {
          id: steveFlip
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: panel.steveW
          height: panel.steveH

          // Real texture — stays visible for Herobrine (frozen frame 0).
          AnimatedImage {
            id: steveAnim
            anchors.fill: parent
            source: Qt.resolvedUrl("steve.gif")
            sourceSize: Qt.size(panel.steveW, panel.steveH)
            visible: status === AnimatedImage.Ready
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
            visible: steveAnim.status !== AnimatedImage.Ready && status === Image.Ready
          }

          // Small sharp-corner glow behind Herobrine.
          Rectangle {
            id: herobrineGlow
            visible: root.herobrine
            anchors.fill: parent
            anchors.margins: -3 * panel.s
            color: "#28ffffff"
            radius: 0
            z: -1
          }
          Rectangle {
            id: herobrineGlow2
            visible: root.herobrine
            anchors.fill: parent
            anchors.margins: -1 * panel.s
            color: "#40ffffff"
            radius: 0
            z: -1
          }

          // White eyes + evil smile painted over the real texture.
          Canvas {
            id: herobrineOverlay
            anchors.fill: parent
            visible: root.herobrine
            z: 10
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              if (!root.herobrine || width <= 0 || height <= 0) return
              // Resolve the painted image rect under PreserveAspectFit so the
              // overlay lands on the face whether steve.gif (250×393) or
              // steve.png (48×59) is showing.
              var srcW = 48, srcH = 59
              if (steveAnim.status === AnimatedImage.Ready && steveAnim.sourceSize.width > 0) {
                srcW = steveAnim.sourceSize.width
                srcH = steveAnim.sourceSize.height
              } else if (steveImg.status === Image.Ready && steveImg.sourceSize.width > 0) {
                srcW = steveImg.sourceSize.width
                srcH = steveImg.sourceSize.height
              }
              // Prefer intrinsic image size when available (more accurate than sourceSize).
              if (steveAnim.status === AnimatedImage.Ready && steveAnim.implicitWidth > 0) {
                srcW = steveAnim.implicitWidth
                srcH = steveAnim.implicitHeight
              } else if (steveImg.status === Image.Ready && steveImg.sourceSize.width > 0) {
                // sourceSize is requested decode size; use natural if set
                if (steveImg.source.width > 0) { srcW = steveImg.source.width; srcH = steveImg.source.height }
              }
              var ar = srcW / srcH
              var boxAR = width / height
              var imgW, imgH, ox, oy
              if (boxAR > ar) {
                imgH = height; imgW = height * ar; ox = (width - imgW) / 2; oy = 0
              } else {
                imgW = width; imgH = width / ar; ox = 0; oy = (height - imgH) / 2
              }
              // Map face features from the 48×59 steve.png layout onto the
              // displayed image (proportions hold across texture variants).
              var sx = imgW / 48, sy = imgH / 59
              function R(x, y, w, h) {
                ctx.fillRect(ox + x * sx, oy + y * sy, w * sx, h * sy)
              }
              ctx.fillStyle = "#ffffff"
              // Lightest eye pixels on OG Steve (steve.png 48×59):
              // left iris+sclera shifted 4px left (screen-left was misaligned);
              // right sclera (31-32,8-10) was correct.
              R(20, 8, 4, 2)   // left eye
              R(31, 8, 2, 3)   // right eye
              // Slim evil smile under the nose.
              R(22, 14, 8, 1)
              R(21, 13, 2, 1)
              R(29, 13, 2, 1)
            }
          }

          // Fallback only if neither texture loads.
          Canvas {
            id: steveFallback
            anchors.fill: parent
            visible: steveAnim.status !== AnimatedImage.Ready && steveImg.status !== Image.Ready
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
