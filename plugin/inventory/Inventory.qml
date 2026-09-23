import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property bool opened: false
  function open(payload) { opened = true }
  function close() { opened = false }

  property int guiScale: 2
  property int hoveredSlot: -1
  property string tipText: ""
  property real tipX: 0
  property real tipY: 0
  property bool tipVisible: false

  function showTip(text, x, y) {
    tipText = String(text || "")
    tipX = x
    tipY = y
    tipVisible = tipText.length > 0
  }
  function hideTip() {
    tipVisible = false
    tipHovered = -1
    hoveredSlot = -1
  }
  property int tipHovered: -1

  // Original pixel-art helpers (no Mojang assets).
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

  function launch(i) {
    var it = slots[i]
    if (it && it.cmd && it.cmd.length)
      Quickshell.execDetached(it.cmd)
  }

  // --- Inventory layout (base units, * guiScale) ---
  // Classic proportions: 2×2 craft + player/armor strip, 3×9 main, 9 hotbar.
  readonly property int pad: 7
  readonly property int slot: 16
  readonly property int pitch: 18
  readonly property int cols: 9
  readonly property int mainRows: 3
  readonly property int craftSlot: 12
  readonly property int craftPitch: 16
  readonly property int playerW: 32
  readonly property int playerH: 32
  readonly property int armorCols: 1

  // y layout (base): title 4, top section 16..68, main 76.., hotbar after main+4
  readonly property int titleY: 6
  readonly property int topY: 16
  readonly property int craftX: 98
  readonly property int craftResultX: 154
  readonly property int craftY: 18
  readonly property int playerX: 50
  readonly property int playerY: 18
  readonly property int armorX: 8
  readonly property int armorY: 18
  readonly property int mainY: 84
  readonly property int hotbarY: mainY + mainRows * pitch + 4
  readonly property int panelW: 176
  readonly property int panelH: hotbarY + pitch + pad

  // Slot indexes: 0-3 armor, 4-7 craft, 8 result, 9-35 main (27), 36-44 hotbar (9)
  readonly property int armorBase: 0
  readonly property int craftBase: 4
  readonly property int resultIdx: 8
  readonly property int mainBase: 9
  readonly property int hotbarBase: 36
  readonly property int slotCount: 45

  // Compact brand sprites (also used for hotbar row). Defined before `slots`.
  readonly property var gridBrave: [
    "..ooooo..",
    ".oWWWoW..",
    ".oWoooWo.",
    ".oWoooWo.",
    ".oWWWoWo.",
    ".oooooWW.",
    ".oWoooWW.",
    "..ooooo..",
    "........."
  ]
  readonly property var mapBrave: { "o": "#fb542b", "W": "#ffffff", ".": "#00000000" }

  readonly property var gridTerminal: [
    "#########",
    "#kkkkkkk#",
    "#kg#kkkk#",
    "#k.kg#kk#",
    "#k.k.kg#.",
    "#k.kg###k",
    "#kg#kkkk#",
    "#kggkkkk#",
    "#########"
  ]
  readonly property var mapTerminal: { "#": "#0a0a0c", "k": "#141418", "g": "#3ddf6e", ".": "#141418" }

  readonly property var gridOpenCode: [
    "#########",
    "#.......#",
    "#.#####.#",
    "#.#...#.#",
    "#.#.#.#.#",
    "#.#...#.#",
    "#.#####.#",
    "#.......#",
    "#########"
  ]
  readonly property var mapOpenCode: { "#": "#211e1e", ".": "#f2f0ec" }

  readonly property var gridObsidian: [
    "....#....",
    "...#p#...",
    "..#pPp#..",
    ".#pPPPp#.",
    "#pPPPPPp#",
    "#pPPPPPp#",
    ".#pPPPp#.",
    "..#pPp#..",
    "...#p#..."
  ]
  readonly property var mapObsidian: { "#": "#1a1030", "p": "#6d3ccc", "P": "#b48cff" }

  readonly property var gridX: [
    "#########",
    "#WW####WW",
    "#.WWW.WW#",
    "#..WWW.W#",
    "#...WWW..",
    "#..WWW.W#",
    "#.WWW.WW#",
    "#WW####WW",
    "#########"
  ]
  readonly property var mapX: { "#": "#0d0d0d", "W": "#f5f5f5", ".": "#0d0d0d" }

  readonly property var gridYakihonne: [
    "#########",
    "#wwwwwww#",
    "#wWWwwWWw",
    "#wwwWWwww",
    "#wwWWwwww",
    "#wwwWwwww",
    "#wWWwwWWw",
    "#wwwwwww#",
    "#########"
  ]
  readonly property var mapYakihonne: { "#": "#4a0848", "w": "#f7f2f7", "W": "#840c84" }

  readonly property var gridFiles: [
    ".bb......",
    ".bbbbbb..",
    "#########",
    "#bbbbbbb#",
    "#bbbbbbb#",
    "#bbbbbbb#",
    "#bbbbbbb#",
    "#bbbbbbb#",
    "#########"
  ]
  readonly property var mapFiles: { "#": "#0a2a4a", "b": "#4a9eff", ".": "#00000000" }

  readonly property var gridProton: [
    "#########",
    "#ppppppp#",
    "#pPPPPpp#",
    "#pPpppPpp",
    "#pPPppPPp",
    "#pPPpPPpp",
    "#pPpPPpPp",
    "#pPPPPPpp",
    "#########"
  ]
  readonly property var mapProton: { "#": "#2a1a6a", "p": "#6d4aff", "P": "#8b6cff" }

  readonly property var gridYoutube: [
    ".#######.",
    "#rrrrrrr#",
    "#rWWrrrrr",
    "#rWWWrrrr",
    "#rWWWWrrr",
    "#rWWWrrrr",
    "#rWWrrrrr",
    "#rrrrrrr#",
    ".#######."
  ]
  readonly property var mapYoutube: { "#": "#7a0000", "r": "#ff0000", "W": "#ffffff" }

  // Items placed by index (armor/craft mostly empty; main+hotbar launchers).
  // Hotbar row mirrors HUD order for muscle memory.
  readonly property var slots: {
    var a = new Array(slotCount)
    // Main storage (27) — extra launchers
    a[9]  = { name: "LibreOffice Writer", cmd: ["uwsm-app", "--", "libreoffice", "--writer"] }
    a[10] = { name: "LibreOffice Calc", cmd: ["uwsm-app", "--", "libreoffice", "--calc"] }
    a[11] = { name: "LibreOffice Impress", cmd: ["uwsm-app", "--", "libreoffice", "--impress"] }
    a[12] = { name: "Docker", cmd: ["omarchy-launch-terminal", "docker", "ps"] }
    a[13] = { name: "btop", cmd: ["omarchy-launch-terminal", "btop"] }
    a[14] = { name: "OBS Studio", cmd: ["uwsm-app", "--", "obs"] }
    a[15] = { name: "Inkscape", cmd: ["uwsm-app", "--", "inkscape"] }
    a[16] = { name: "Pinta", cmd: ["uwsm-app", "--", "pinta"] }
    a[17] = { name: "Evince (PDF)", cmd: ["uwsm-app", "--", "evince"] }
    a[18] = { name: "mpv", cmd: ["omarchy-launch-terminal", "mpv"] }
    a[19] = { name: "imv", cmd: ["uwsm-app", "--", "imv"] }
    a[20] = { name: "Kdenlive", cmd: ["uwsm-app", "--", "kdenlive"] }
    a[21] = { name: "ChatGPT", cmd: ["uwsm-app", "--", "chatgpt"] }
    a[22] = { name: "Google Maps", cmd: ["omarchy-launch-webapp", "https://maps.google.com/"] }
    a[23] = { name: "LocalSend", cmd: ["uwsm-app", "--", "localsend"] }
    a[24] = { name: "Proton VPN", cmd: ["uwsm-app", "--", "protonvpn-app"] }
    a[25] = { name: "Rofi launcher", cmd: ["rofi", "-show", "drun"] }
    a[26] = { name: "Neovim", cmd: ["omarchy-launch-terminal", "nvim"] }
    a[27] = { name: "Disks", cmd: ["uwsm-app", "--", "gnome-disks"] }
    a[28] = { name: "Moonlight", cmd: ["uwsm-app", "--", "moonlight"] }
    a[29] = { name: "Xournal++", cmd: ["uwsm-app", "--", "xournalpp-wrapper"] }
    a[30] = { name: "System monitor", cmd: ["omarchy-launch-terminal", "btop"] }
    a[31] = { name: "File manager", cmd: ["omarchy-launch-nautilus"] }
    a[32] = { name: "Printer", cmd: ["system-config-printer"] }
    a[33] = { name: "Clipboard", cmd: ["omarchy-shell", "shell", "toggle", "omarchy.clipboard", "{}"] }
    a[34] = { name: "Emoji picker", cmd: ["omarchy-shell", "shell", "toggle", "omarchy.emojis", "{}"] }
    a[35] = { name: "Theme menu", cmd: ["omarchy-menu", "toggle", "theme"] }
    // Hotbar row = same 9 as HUD
    a[36] = { name: "Brave Search", cmd: ["omarchy-launch-browser", "https://search.brave.com"],
              rows: root.gridBrave, colors: root.mapBrave }
    a[37] = { name: "Terminal", cmd: ["omarchy-launch-terminal"],
              rows: root.gridTerminal, colors: root.mapTerminal }
    a[38] = { name: "OpenCode", cmd: ["omarchy-launch-terminal", "opencode"],
              rows: root.gridOpenCode, colors: root.mapOpenCode }
    a[39] = { name: "Obsidian", cmd: ["uwsm-app", "--", "obsidian"],
              rows: root.gridObsidian, colors: root.mapObsidian }
    a[40] = { name: "X", cmd: ["omarchy-launch-webapp", "https://x.com/"],
              rows: root.gridX, colors: root.mapX }
    a[41] = { name: "Yakihonne", cmd: ["omarchy-launch-webapp", "https://yakihonne.com"],
              rows: root.gridYakihonne, colors: root.mapYakihonne }
    a[42] = { name: "Files", cmd: ["omarchy-launch-nautilus"],
              rows: root.gridFiles, colors: root.mapFiles }
    a[43] = { name: "Proton Mail", cmd: ["omarchy-launch-webapp", "https://mail.proton.me"],
              rows: root.gridProton, colors: root.mapProton }
    a[44] = { name: "YouTube", cmd: ["omarchy-launch-webapp", "https://youtube.com/"],
              rows: root.gridYoutube, colors: root.mapYoutube }
    return a
  }

  // Letter tile for main slots without brand art (first letter of name)
  function letterTile(name) {
    var ch = (name || "?").charAt(0).toUpperCase()
    var bg = "#3a3a48"
    var fg = "#e8e8f0"
    return {
      rows: [
        "#########",
        "#.......#",
        "#.#####.#",
        "#.#...#.#",
        "#.##.##.#",
        "#.#...#.#",
        "#.#####.#",
        "#.......#",
        "#########"
      ],
      colors: { "#": bg, ".": bg, "L": fg },
      letter: ch
    }
  }

  function slotOrigin(i) {
    // returns base-unit {x,y} of slot content origin inside panel
    if (i >= armorBase && i < armorBase + 4)
      return { x: armorX, y: armorY + (i - armorBase) * pitch }
    if (i >= craftBase && i < craftBase + 4) {
      var cx = (i - craftBase) % 2
      var cy = Math.floor((i - craftBase) / 2)
      return { x: craftX + cx * craftPitch, y: craftY + cy * craftPitch }
    }
    if (i === resultIdx)
      return { x: craftResultX, y: craftY + 2 }
    if (i >= mainBase && i < mainBase + 27) {
      var mi = i - mainBase
      var mx = mi % cols
      var my = Math.floor(mi / cols)
      return { x: pad + mx * pitch, y: mainY + my * pitch }
    }
    if (i >= hotbarBase && i < hotbarBase + 9) {
      var hi = i - hotbarBase
      return { x: pad + hi * pitch, y: hotbarY }
    }
    return { x: -1, y: -1 }
  }

  function hitSlot(px, py) {
    // px, py in base units
    for (var i = 0; i < slotCount; i++) {
      var o = slotOrigin(i)
      if (o.x < 0) continue
      var sz = (i === resultIdx || (i >= craftBase && i < craftBase + 4)) ? craftSlot : slot
      if (i === resultIdx) sz = craftSlot
      if (i >= craftBase && i < craftBase + 4) sz = craftSlot
      if (px >= o.x && px < o.x + sz && py >= o.y && py < o.y + sz)
        return i
    }
    return -1
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "minecraft-inventory"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: hitRoot }

    readonly property int s: root.guiScale
    readonly property int pw: root.panelW * s
    readonly property int ph: root.panelH * s
    readonly property int ox: Math.round((width - pw) / 2)
    readonly property int oy: Math.round((height - ph) / 2)

    // Click-outside close + full-screen dim + centered panel
    Item {
      id: hitRoot
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.close()

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
      }

      // Panel body (blocks click-through so outside-click still closes)
      Item {
        id: panelBody
        x: panel.ox
        y: panel.oy
        width: panel.pw
        height: panel.ph
        focus: true

        Keys.onEscapePressed: root.close()

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          z: -1
          onPositionChanged: function(mouse) {
            var bx = mouse.x / panel.s
            var by = mouse.y / panel.s
            var i = root.hitSlot(bx, by)
            root.hoveredSlot = i
            if (i >= 0) {
              var it = root.slots[i]
              var label = it ? it.name : ""
              if (label) {
                var o = root.slotOrigin(i)
                root.showTip(label, panel.ox + (o.x + 8) * panel.s, panel.oy + o.y * panel.s - 4 * panel.s)
              } else {
                root.hideTip()
              }
            } else {
              root.hideTip()
            }
          }
          onExited: root.hideTip()
          onClicked: function(mouse) {
            var bx = mouse.x / panel.s
            var by = mouse.y / panel.s
            var i = root.hitSlot(bx, by)
            if (i >= 0)
              root.launch(i)
          }
        }

        Canvas {
          id: invCanvas
          anchors.fill: parent
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Component.onCompleted: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return

            var s = panel.s

            // Dim backdrop
            ctx.fillStyle = "rgba(0, 0, 0, 0.45)"
            ctx.fillRect(0, 0, width, height)

            // --- GUI panel (MC-like bevel, original colors) ---
            var px = 0
            var py = 0
            var pw = root.panelW * s
            var ph = root.panelH * s
            ctx.fillStyle = "#c6c6c6"
            ctx.fillRect(px, py, pw, ph)
            // outer light top-left / dark bottom-right
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(px, py, pw, s)
            ctx.fillRect(px, py, s, ph)
            ctx.fillStyle = "#555555"
            ctx.fillRect(px, py + ph - s, pw, s)
            ctx.fillRect(px + pw - s, py, s, ph)
            ctx.fillStyle = "#000000"
            ctx.fillRect(px, py + ph - 2 * s, pw, s)
            ctx.fillRect(px + pw - 2 * s, py, s, ph)

            // Title
            ctx.fillStyle = "#404040"
            ctx.font = "bold " + String(8 * s) + "px Monocraft, monospace"
            ctx.textAlign = "left"
            ctx.textBaseline = "top"
            ctx.fillText("Inventory", root.pad * s, root.titleY * s)

            // Player preview well (original stub pixel figure — M5 Steve replaces)
            var plx = root.playerX * s
            var ply = root.playerY * s
            var plw = root.playerW * s
            var plh = root.playerH * s
            ctx.fillStyle = "#8b8b8b"
            ctx.fillRect(plx, ply, plw, plh)
            ctx.fillStyle = "#373737"
            ctx.fillRect(plx, ply, plw, s)
            ctx.fillRect(plx, ply, s, plh)
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(plx, ply + plh - s, plw, s)
            ctx.fillRect(plx + plw - s, ply, s, plh)
            // simple original character silhouette
            drawPlayer(ctx, plx + 6 * s, ply + 4 * s, s)

            // Armor column wells
            for (var a = 0; a < 4; a++) {
              drawSlotFrame(ctx, root.armorX * s, (root.armorY + a * root.pitch) * s, root.slot * s, s, false)
            }

            // Crafting 2×2 + result
            for (var c = 0; c < 4; c++) {
              var co = root.slotOrigin(root.craftBase + c)
              drawSlotFrame(ctx, co.x * s, co.y * s, root.craftSlot * s, s, false)
            }
            var ro = root.slotOrigin(root.resultIdx)
            drawSlotFrame(ctx, ro.x * s, ro.y * s, root.craftSlot * s, s, false)
            // arrow between craft and result
            drawArrow(ctx, (root.craftX + 34) * s, (root.craftY + 8) * s, s)

            // Main 3×9
            for (var m = 0; m < 27; m++) {
              var mo = root.slotOrigin(root.mainBase + m)
              drawSlotFrame(ctx, mo.x * s, mo.y * s, root.slot * s, s, false)
            }
            // Hotbar strip bg
            ctx.fillStyle = "#8b8b8b"
            ctx.fillRect((root.pad - 1) * s, (root.hotbarY - 1) * s, (root.cols * root.pitch + 2) * s, (root.slot + 2) * s)

            // Hotbar slots
            for (var h = 0; h < 9; h++) {
              var ho = root.slotOrigin(root.hotbarBase + h)
              drawSlotFrame(ctx, ho.x * s, ho.y * s, root.slot * s, s, false)
            }

            // Icons + hover highlight
            for (var i = 0; i < root.slotCount; i++) {
              var it = root.slots[i]
              var o = root.slotOrigin(i)
              if (o.x < 0) continue
              var sz = (i >= root.craftBase && i <= root.resultIdx) ? root.craftSlot : root.slot
              if (i === root.resultIdx) sz = root.craftSlot

              if (i === root.hoveredSlot) {
                ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                ctx.fillRect(o.x * s, o.y * s, sz * s, sz * s)
              }
              if (!it) continue

              if (it.rows) {
                var iw = it.rows[0].length
                var ih = it.rows.length
                var iox = o.x + Math.floor((sz - iw) / 2)
                var ioy = o.y + Math.floor((sz - ih) / 2)
                root.paintGrid(ctx, iox * s, ioy * s, s, it.rows, it.colors)
              } else {
                // letter tile centered in slot
                var t = root.letterTile(it.name)
                var tw = t.rows[0].length
                var th = t.rows.length
                var tx = o.x + Math.floor((sz - tw) / 2)
                var ty = o.y + Math.floor((sz - th) / 2)
                root.paintGrid(ctx, tx * s, ty * s, s, t.rows, t.colors)
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText(t.letter, (o.x + sz / 2) * s, (o.y + sz / 2) * s)
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
              }
            }
          }

          function drawSlotFrame(ctx, x, y, sz, s, selected) {
            // MC-like depressed slot
            ctx.fillStyle = "#8b8b8b"
            ctx.fillRect(x, y, sz, sz)
            ctx.fillStyle = "#373737"
            ctx.fillRect(x, y, sz, s)
            ctx.fillRect(x, y, s, sz)
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(x, y + sz - s, sz, s)
            ctx.fillRect(x + sz - s, y, s, sz)
            if (selected) {
              ctx.strokeStyle = "#ffffff"
              ctx.lineWidth = s
              ctx.strokeRect(x - s, y - s, sz + 2 * s, sz + 2 * s)
            }
          }

          function drawArrow(ctx, x, y, s) {
            ctx.fillStyle = "#8b8b8b"
            // shaft
            ctx.fillRect(x, y, 8 * s, 2 * s)
            // head
            ctx.fillRect(x + 6 * s, y - 2 * s, 2 * s, 6 * s)
            ctx.fillRect(x + 8 * s, y - s, 2 * s, 4 * s)
            ctx.fillRect(x + 10 * s, y, 2 * s, 2 * s)
          }

          function drawPlayer(ctx, x, y, s) {
            // Original stub figure (blue shirt / purple pants) — placeholder for M5 Steve
            // head 8×8
            ctx.fillStyle = "#c8a27a"
            ctx.fillRect(x + 4 * s, y, 8 * s, 8 * s)
            ctx.fillStyle = "#3a2a1a"
            ctx.fillRect(x + 4 * s, y, 8 * s, 2 * s)
            // eyes
            ctx.fillStyle = "#3b5dc9"
            ctx.fillRect(x + 5 * s, y + 4 * s, 2 * s, 2 * s)
            ctx.fillRect(x + 9 * s, y + 4 * s, 2 * s, 2 * s)
            // body
            ctx.fillStyle = "#3dafd0"
            ctx.fillRect(x + 4 * s, y + 8 * s, 8 * s, 10 * s)
            // arms
            ctx.fillStyle = "#c8a27a"
            ctx.fillRect(x + 1 * s, y + 8 * s, 3 * s, 10 * s)
            ctx.fillRect(x + 12 * s, y + 8 * s, 3 * s, 10 * s)
            // legs
            ctx.fillStyle = "#4a3fa0"
            ctx.fillRect(x + 4 * s, y + 18 * s, 4 * s, 8 * s)
            ctx.fillRect(x + 8 * s, y + 18 * s, 4 * s, 8 * s)
          }
        }
      }
    }

    // Tooltip bubble
    Rectangle {
      id: tipBubble
      z: 50
      visible: root.opened && root.tipVisible
      color: Qt.rgba(15 / 255, 15 / 255, 18 / 255, 0.95)
      border.color: "#000000"
      border.width: Math.max(1, panel.s / 2)
      radius: 3 * panel.s
      width: tipLabel.implicitWidth + 8 * panel.s
      height: tipLabel.implicitHeight + 6 * panel.s
      x: {
        var mid = root.tipX - width / 2
        return Math.max(2 * panel.s, Math.min(panel.width - width - 2 * panel.s, mid))
      }
      y: Math.max(2 * panel.s, root.tipY - height)
      Text {
        id: tipLabel
        anchors.centerIn: parent
        text: root.tipText
        color: "#ffffff"
        font {
          family: "Monocraft"
          pixelSize: 7 * panel.s
        }
      }
    }
  }
}
