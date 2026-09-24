import QtQuick
import qs.Commons
import Quickshell
import Quickshell.Io

// Minecraft Cube — bar widget next to the Omarchy menu button.
// Click to toggle the minecraft theme (same as SUPER+M). The cube is full
// colour while the theme is on and greyscale while it is off; state comes
// from watching the theme marker file, so idle cost is zero (no timers).
//
// Sizing mirrors the Omarchy menu button (the logo) exactly: same slot
// formula WidgetButton uses for it — logo glyph advance + the same margins,
// barSize tall — and the block itself fills the logo glyph's ink box, so in
// every theme the cube is the same size as the logo beside it.
Item {
  id: root

  // Injected by the bar at load time (see plugins/bar/README.md).
  property var bar
  property string moduleName
  property var settings

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  // The glyph WidgetButton paints for the menu button, kept offscreen purely
  // for its font metrics. Font size is the same Style.font.body the button
  // labels with, so the numbers track the theme automatically.
  TextMetrics {
    id: logo
    text: "\ue900"
    font.family: "omarchy"
    font.pixelSize: Style.font.body
  }

  // Ink box of the logo glyph — the visible square the cube must match.
  readonly property int inkW: Math.max(1, Math.round(logo.tightBoundingRect.width))
  readonly property int inkH: Math.max(1, Math.round(logo.tightBoundingRect.height))

  // Same formulas as WidgetButton with the menu button's margins (7.5
  // horizontal, 6 vertical), so the cube occupies an identical slot.
  implicitWidth: vertical
    ? barSize
    : Math.max(12, logo.advanceWidth + 2 * Style.spaceReal(7.5))
  implicitHeight: vertical
    ? Math.max(12, logo.height + 2 * Style.spaceReal(6))
    : barSize

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

  // 8x8 pixel grass block; cells are mapped to whole pixels proportionally
  // (Math.round of each edge), so the block stays crisp at any box size.
  readonly property var grid: [
    "11211311",
    "12113112",
    "11121111",
    "44144414",
    "55655755",
    "56558556",
    "75565585",
    "55855655"
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
    // The block fills exactly the logo glyph's ink box (10px next to a 12px
    // body font, larger when the theme raises the base font size).
    width: root.inkW
    height: root.inkH
    smooth: false
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var g = root.grid
      var n = g.length
      var pal = root.active ? root.palOn : root.palOff
      for (var r = 0; r < n; r++) {
        var y0 = Math.round(r * height / n)
        var y1 = Math.round((r + 1) * height / n)
        var row = g[r]
        for (var c = 0; c < n; c++) {
          var col = pal[row[c]]
          if (!col) continue
          var x0 = Math.round(c * width / n)
          var x1 = Math.round((c + 1) * width / n)
          ctx.fillStyle = col
          ctx.fillRect(x0, y0, x1 - x0, y1 - y0)
        }
      }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
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
