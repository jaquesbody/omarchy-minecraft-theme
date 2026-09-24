import QtQuick
import Quickshell
import Quickshell.Io

// Minecraft Cube — bar widget next to the Omarchy menu button.
// Click to toggle the minecraft theme (same as SUPER+M). The cube is full
// colour while the theme is on and greyscale while it is off; state comes
// from watching the theme marker file, so idle cost is zero (no timers).
Item {
  id: root

  // Injected by the bar at load time (see plugins/bar/README.md).
  property var bar
  property string moduleName
  property var settings

  implicitWidth: 28
  implicitHeight: bar ? bar.barSize : 26

  property bool active: false

  FileView {
    id: themeName
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.active = String(text()).trim() === "minecraft"
    // Re-read on change (including first creation) before loading — text() is
    // stale in the change signal itself, so route through reload -> onLoaded.
    onFileChanged: reload()
    onLoadFailed: root.active = false
  }

  onActiveChanged: cube.requestPaint()

  // 9x9 pixel grass block; cell size is width/9 = 2px, so every pixel stays
  // sharp at the whole-number UI scale.
  readonly property var grid: [
    "112113112",
    "121131121",
    "111211113",
    "441444144",
    "556557555",
    "565585565",
    "755655855",
    "558556557",
    "565575585"
  ]
  readonly property var palOn: ({
    "1": "#6bbd45", "2": "#7fd157", "3": "#57a736", "4": "#4e9430",
    "5": "#8b6748", "6": "#9c7a5a", "7": "#7a573c", "8": "#674a33"
  })
  readonly property var palOff: ({
    "1": "#9a9a9a", "2": "#adadad", "3": "#878787", "4": "#767676",
    "5": "#8f8f8f", "6": "#a0a0a0", "7": "#7e7e7e", "8": "#6c6c6c"
  })

  Canvas {
    id: cube
    anchors.centerIn: parent
    width: 18
    height: 18
    smooth: false
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var n = 9
      var cell = width / n
      var pal = root.active ? root.palOn : root.palOff
      var g = root.grid
      for (var r = 0; r < g.length; r++) {
        var row = g[r]
        for (var c = 0; c < row.length; c++) {
          var col = pal[row[c]]
          if (!col) continue
          ctx.fillStyle = col
          ctx.fillRect(c * cell, r * cell, cell, cell)
        }
      }
    }
    onWidthChanged: requestPaint()
    Component.onCompleted: requestPaint()
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: {
      if (bar)
        bar.run(Quickshell.env("HOME") + "/.local/bin/minecraft-theme-toggle")
    }
    onEntered: {
      if (bar)
        bar.showTooltip(root, root.active
          ? "Minecraft theme: ON — click to switch off"
          : "Minecraft theme: OFF — click to switch on")
    }
    onExited: {
      if (bar) bar.hideTooltip(root)
    }
  }
}
