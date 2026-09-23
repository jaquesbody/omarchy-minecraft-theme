import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property bool opened: false
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  function open(payload) {
    var p = {}
    try {
      p = typeof payload === "string" && payload ? JSON.parse(payload) : (payload || {})
    } catch (e) {}
    opened = true
    if (p && p.tab !== undefined) {
      var ti = Number(p.tab)
      if (ti >= 0 && ti < menuTabs.length) {
        selectedTab = ti
        menuPath = p.path ? p.path : []
        if (menuTabs[ti].route === "apps") loadApps()
        if (invCanvas) invCanvas.requestPaint()
      }
    }
    if (appRefreshTimer) appRefreshTimer.restart()
  }
  function close() {
    opened = false
    selectedTab = -1
    menuPath = []
    hoveredSlot = -1
    hideTip()
  }

  property int guiScale: 2
  property int hoveredSlot: -1
  property string tipText: ""
  property real tipX: 0
  property real tipY: 0
  property bool tipVisible: false

  // Menu tab state: -1 = classic inventory; >=0 shows that route's children.
  property int selectedTab: -1
  onSelectedTabChanged: {
    if (invCanvas) invCanvas.requestPaint()
  }
  property var menuPath: []
  onMenuPathChanged: {
    if (invCanvas) invCanvas.requestPaint()
  }
  property var menuTree: []
  property var appRows: []
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  function menuItems() {
    if (selectedTab < 0) return []
    var tab = menuTabs[selectedTab]
    var node = menuTree[selectedTab]
    if (!tab || !node) return []
    // node = [route, icon, label, children]
    var kids = node[3] || []
    var cur = kids
    for (var p = 0; p < menuPath.length; p++) {
      var idx = menuPath[p]
      if (!cur[idx]) return []
      cur = cur[idx][4] || []
    }
    return cur
  }

  function menuItemAt(i) {
    var items = menuItems()
    if (i < 0 || i >= items.length) return null
    return items[i]
  }

  function menuTitle() {
    if (selectedTab < 0) return ""
    var tab = menuTabs[selectedTab]
    var label = tab ? tab.label : ""
    var items = menuItems()
    if (menuPath.length && items.length === 0) {
      // parent label from path walk
      var node = menuTree[selectedTab]
      var kids = node ? (node[3] || []) : []
      for (var p = 0; p < menuPath.length; p++) {
        if (!kids[menuPath[p]]) break
        label = kids[menuPath[p]][1]
        kids = kids[menuPath[p]][4] || []
      }
    } else if (menuPath.length) {
      var n2 = menuTree[selectedTab]
      var k2 = n2 ? (n2[3] || []) : []
      for (var q = 0; q < menuPath.length; q++) {
        if (!k2[menuPath[q]]) break
        k2 = k2[menuPath[q]][4] || []
      }
      // title stays tab label; header icon is tab icon
    }
    return label
  }

  function currentMenuChildren() {
    if (selectedTab < 0) return []
    var node = menuTree[selectedTab]
    if (!node) return []
    var kids = node[3] || []
    var cur = kids
    for (var p = 0; p < menuPath.length; p++) {
      if (!cur[menuPath[p]]) return []
      cur = cur[menuPath[p]][4] || []
    }
    return cur
  }

  function launchMenuItem(i) {
    var items = menuItems()
    var it = items[i]
    if (!it) return
    var action = String(it[2] || "")
    var provider = String(it[3] || "")
    var kids = it[4] || []
    if (kids.length > 0) {
      menuPath = menuPath.concat([i])
      invCanvas.requestPaint()
      return
    }
    if (provider === "apps") return
    if (action.length) {
      Quickshell.execDetached(["bash", "-lc", action])
      root.close()
      return
    }
    // Non-actionable leaf (submenu without children in snapshot) — no-op
  }

  function goBackMenu() {
    if (menuPath.length > 0) {
      menuPath = menuPath.slice(0, menuPath.length - 1)
      invCanvas.requestPaint()
      return true
    }
    return false
  }

  function loadApps() {
    try {
      var values = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications)
        ? (DesktopEntries.applications.values || []) : []
      var out = []
      for (var i = 0; i < values.length; i++) {
        var e = values[i]
        if (!e || e.noDisplay) continue
        var id = String(e.id || "")
        if (!id) continue
        var name = String(e.name || id)
        if (!name) continue
        out.push({
          name: name,
          id: id,
          sub: String(e.genericName || "")
        })
      }
      out.sort(function(a, b) {
        var an = a.name.toLowerCase()
        var bn = b.name.toLowerCase()
        if (an < bn) return -1
        if (an > bn) return 1
        return 0
      })
      appRows = out
      if (opened && invCanvas) invCanvas.requestPaint()
    } catch (err) {}
  }

  function launchApp(a) {
    if (!a || !a.id) return
    if (appLibrary && typeof appLibrary.launch === "function") {
      appLibrary.launch(a.id, a.name)
      return
    }
    Quickshell.execDetached([
      "uwsm-app", "--", "gtk-launch", a.id + ".desktop"
    ])
  }

  Timer {
    id: appRefreshTimer
    interval: 50
    onTriggered: root.loadApps()
  }

  Connections {
    target: typeof DesktopEntries !== "undefined" ? DesktopEntries.applications : null
    function onValuesChanged() { root.loadApps() }
    enabled: target !== null
  }

  FileView {
    id: menuFile
    path: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.jaquesbody.minecraft-inventory/menu-data.json"
    watchChanges: false
    printErrors: true
    onLoaded: {
      try { root.menuTree = JSON.parse(text()) } catch (e) { root.menuTree = [] }
      if (opened) invCanvas.requestPaint()
    }
  }

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

  // y layout (base): tabs 0..tabH, then classic layout shifted by tabH
  readonly property int tabH: 14
  readonly property int titleY: 6 + tabH
  readonly property int topY: 16 + tabH
  readonly property int craftX: 98
  readonly property int craftResultX: 154
  readonly property int craftY: 18 + tabH
  readonly property int playerX: 50
  readonly property int playerY: 18 + tabH
  readonly property int armorX: 8
  readonly property int armorY: 18 + tabH
  readonly property int mainY: 84 + tabH
  readonly property int hotbarY: mainY + mainRows * pitch + 4
  readonly property int panelW: 176
  readonly property int panelH: hotbarY + pitch + pad

  // Omarchy menu root tabs — nerd-font glyphs from omarchy-menu.jsonc icons.
  readonly property var menuTabs: [
    { route: "apps", icon: "\u{f003b}", label: "Apps" },
    { route: "learn", icon: "\u{f09d1}", label: "Learn" },
    { route: "trigger", icon: "\u{f14de}", label: "Trigger" },
    { route: "style", icon: "\u{ebcf}", label: "Style" },
    { route: "setup", icon: "\u{e615}", label: "Setup" },
    { route: "install", icon: "\u{f0249}", label: "Install" },
    { route: "remove", icon: "\u{f0b4c}", label: "Remove" },
    { route: "update", icon: "\u{f021}", label: "Update" },
    { route: "about", icon: "\u{ea74}", label: "About" },
    { route: "system", icon: "\u{f011}", label: "System" }
  ]
  property int hoveredTab: -1

  function hitTab(px, py) {
    if (py < 0 || py >= tabH || px < 2 || px >= panelW - 2) return -1
    var n = menuTabs.length
    var gap = 1
    var w = (panelW - 4 - gap * (n - 1)) / n
    var i = Math.floor((px - 2) / (w + gap))
    return (i >= 0 && i < n) ? i : -1
  }
  function openTab(i) {
    i = Number(i)
    if (!(i >= 0 && i < menuTabs.length)) return
    if (selectedTab === i) {
      // Second click on active tab: leave submenus, then deselect to classic.
      if (menuPath.length > 0) {
        menuPath = []
      } else {
        selectedTab = -1
      }
    } else {
      selectedTab = i
      menuPath = []
      if (menuTabs[i].route === "apps") root.loadApps()
    }
    hoveredSlot = -1
    hideTip()
    invCanvas.requestPaint()
  }

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
    ".ooooooo.",
    ".ooooooo.",
    ".ooooooo.",
    ".ooooooo.",
    ".ooooooo.",
    "...ooo...",
    "....o....",
    "........."
  ]
  readonly property var mapBrave: { "o": "#fb542b", "#": "#3a1004", ".": "#00000000" }

  readonly property var gridTerminal: [
    "#########",
    "#kkkkkkk#",
    "#kg#kkkk#",
    "#kkkgkkk#",
    "#kkkkg###",
    "#kkkkkkk#",
    "#kg######",
    "#kgggggg#",
    "#########"
  ]
  readonly property var mapTerminal: { "#": "#0a0a0c", "k": "#141418", "g": "#3ddf6e" }

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
    "#wWwwwWw#",
    "#wWwwwWw#",
    "#wwWwWww#",
    "#wwwWwww#",
    "#wwwWwww#",
    "#wwwWwww#",
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
    // Main storage (27) — launchers with individual pixel icons
    a[9]  = { name: "LibreOffice Writer", cmd: ["uwsm-app", "--", "libreoffice", "--writer"],
              rows: root.gridWriter, colors: root.mapWriter }
    a[10] = { name: "LibreOffice Calc", cmd: ["uwsm-app", "--", "libreoffice", "--calc"],
              rows: root.gridCalc, colors: root.mapCalc }
    a[11] = { name: "LibreOffice Impress", cmd: ["uwsm-app", "--", "libreoffice", "--impress"],
              rows: root.gridImpress, colors: root.mapImpress }
    a[12] = { name: "Docker", cmd: ["omarchy-launch-terminal", "docker", "ps"],
              rows: root.gridDocker, colors: root.mapDocker }
    a[13] = { name: "btop", cmd: ["omarchy-launch-terminal", "btop"],
              rows: root.gridBtop, colors: root.mapBtop }
    a[14] = { name: "OBS Studio", cmd: ["uwsm-app", "--", "obs"],
              rows: root.gridObs, colors: root.mapObs }
    a[15] = { name: "Inkscape", cmd: ["uwsm-app", "--", "inkscape"],
              rows: root.gridInkscape, colors: root.mapInkscape }
    a[16] = { name: "Pinta", cmd: ["uwsm-app", "--", "pinta"],
              rows: root.gridPinta, colors: root.mapPinta }
    a[17] = { name: "Evince (PDF)", cmd: ["uwsm-app", "--", "evince"],
              rows: root.gridPdf, colors: root.mapPdf }
    a[18] = { name: "mpv", cmd: ["omarchy-launch-terminal", "mpv"],
              rows: root.gridPlay, colors: root.mapPlay }
    a[19] = { name: "imv", cmd: ["uwsm-app", "--", "imv"],
              rows: root.gridImage, colors: root.mapImage }
    a[20] = { name: "Kdenlive", cmd: ["uwsm-app", "--", "kdenlive"],
              rows: root.gridFilm, colors: root.mapFilm }
    a[21] = { name: "ChatGPT", cmd: ["uwsm-app", "--", "chatgpt"],
              rows: root.gridChatgpt, colors: root.mapChatgpt }
    a[22] = { name: "Google Maps", cmd: ["omarchy-launch-webapp", "https://maps.google.com/"],
              rows: root.gridPin, colors: root.mapPin }
    a[23] = { name: "LocalSend", cmd: ["uwsm-app", "--", "localsend"],
              rows: root.gridShare, colors: root.mapShare }
    a[24] = { name: "Proton VPN", cmd: ["uwsm-app", "--", "protonvpn-app"],
              rows: root.gridShield, colors: root.mapShield }
    a[25] = { name: "Rofi launcher", cmd: ["rofi", "-show", "drun"],
              rows: root.gridRofi, colors: root.mapRofi }
    a[26] = { name: "Neovim", cmd: ["omarchy-launch-terminal", "nvim"],
              rows: root.gridNeovim, colors: root.mapNeovim }
    a[27] = { name: "Disks", cmd: ["uwsm-app", "--", "gnome-disks"],
              rows: root.gridDisk, colors: root.mapDisk }
    a[28] = { name: "Moonlight", cmd: ["uwsm-app", "--", "moonlight"],
              rows: root.gridMoon, colors: root.mapMoon }
    a[29] = { name: "Xournal++", cmd: ["uwsm-app", "--", "xournalpp-wrapper"],
              rows: root.gridPen, colors: root.mapPen }
    a[30] = { name: "System monitor", cmd: ["omarchy-launch-terminal", "btop"],
              rows: root.gridChart, colors: root.mapChart }
    a[31] = { name: "File manager", cmd: ["omarchy-launch-nautilus"],
              rows: root.gridFiles, colors: root.mapFiles }
    a[32] = { name: "Printer", cmd: ["system-config-printer"],
              rows: root.gridPrinter, colors: root.mapPrinter }
    a[33] = { name: "Clipboard", cmd: ["omarchy-shell", "shell", "toggle", "omarchy.clipboard", "{}"],
              rows: root.gridClipboard, colors: root.mapClipboard }
    a[34] = { name: "Emoji picker", cmd: ["omarchy-shell", "shell", "toggle", "omarchy.emojis", "{}"],
              rows: root.gridEmoji, colors: root.mapEmoji }
    a[35] = { name: "Theme menu", cmd: ["omarchy-menu", "toggle", "theme"],
              rows: root.gridPalette, colors: root.mapPalette }
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

  // Per-item pixel icons for every filled slot (9×9 unless noted).
  readonly property var gridWriter: [
    "#########",
    "#dwwwwwwd",
    "#dwwwwwwd",
    "#dwWwwWwd",
    "#dwwwwwwd",
    "#dwWwwWwd",
    "#dwwwwwwd",
    "#dddddddd",
    "#########"
  ]
  readonly property var mapWriter: { "#": "#0a3d91", "d": "#1a5fc4", "w": "#e8f0ff", "W": "#1a5fc4" }

  readonly property var gridCalc: [
    "#########",
    "#gwwwwwwg",
    "#gwWwwWwg",
    "#gwwwwwwg",
    "#gwWwwWwg",
    "#gwwwwwwg",
    "#gwwwwwwg",
    "#gggggggg",
    "#########"
  ]
  readonly property var mapCalc: { "#": "#0d7324", "g": "#18a303", "w": "#eaffea", "W": "#0d7324" }

  readonly property var gridImpress: [
    "#########",
    "#ooooooo#",
    "#oWWWooo#",
    "#oWWWooo#",
    "#oWWWoRo#",
    "#oWWoooo#",
    "#oWooooo#",
    "#ooooooo#",
    "#########"
  ]
  readonly property var mapImpress: { "#": "#7a2000", "o": "#d3460f", "W": "#fff0e0", "R": "#ffb080" }

  readonly property var gridDocker: [
    ".........",
    "..bbbb...",
    ".bbbbbb..",
    "bbBbbBbbb",
    "bbBbbBbbb",
    "bbbbbbbb.",
    ".bbbbbb..",
    "..bbbb...",
    "........."
  ]
  readonly property var mapDocker: { "b": "#0db7ed", "B": "#ffffff" }

  readonly property var gridBtop: [
    "#########",
    "#kkkkkkk#",
    "#kgggggk#",
    "#kgkggkk#",
    "#gkggkgg#",
    "#gggkggg#",
    "#kkkkkkk#",
    "#kkkkkkk#",
    "#########"
  ]
  readonly property var mapBtop: { "#": "#0a0a0c", "k": "#141418", "g": "#3ddf6e" }

  readonly property var gridObs: [
    "#########",
    "#ooooooo#",
    "#ooccccco",
    "#occcccc#",
    "#occccco#",
    "#occccco#",
    "#oocccco#",
    "#ooooooo#",
    "#########"
  ]
  readonly property var mapObs: { "#": "#1a1a1a", "o": "#303030", "c": "#e0e0e0" }

  readonly property var gridInkscape: [
    ".........",
    "......aa.",
    ".....aa..",
    "....aa...",
    "...aa....",
    "..aa.....",
    ".aa......",
    "aa.......",
    "a........"
  ]
  readonly property var mapInkscape: { "a": "#2ec4b6" }

  readonly property var gridPinta: [
    ".........",
    "..rrr....",
    ".rrrrr...",
    ".rrrrgg..",
    "..rrggg..",
    "...ggg...",
    "..bbbbb..",
    ".bbbbbbb.",
    "........."
  ]
  readonly property var mapPinta: { "r": "#ff6b6b", "g": "#51cf66", "b": "#4dabf7" }

  readonly property var gridPdf: [
    "#########",
    "#wwwwwww#",
    "#wRwwwww#",
    "#wRRwRww#",
    "#wRwRRww#",
    "#wRwwRww#",
    "#wRRRRww#",
    "#wwwwwww#",
    "#########"
  ]
  readonly property var mapPdf: { "#": "#6a0000", "w": "#fff5f5", "R": "#d92027" }

  readonly property var gridPlay: [
    "#########",
    "#ooooooo#",
    "#oWWoooo#",
    "#oWWWooo#",
    "#oWWWWoo#",
    "#oWWWooo#",
    "#oWWoooo#",
    "#ooooooo#",
    "#########"
  ]
  readonly property var mapPlay: { "#": "#0a0a0c", "o": "#1a1a1e", "W": "#ffffff" }

  readonly property var gridImage: [
    "#########",
    "#ooooooo#",
    "#oGGGGGo#",
    "#oGyyGGo#",
    "#oGGGGGo#",
    "#ooGoooo#",
    "#ooooooo#",
    "#ooooooo#",
    "#########"
  ]
  readonly property var mapImage: { "#": "#0a3040", "o": "#1a6070", "G": "#60c0d0", "y": "#ffe060" }

  readonly property var gridFilm: [
    "#########",
    "#aaaaaaaa",
    "#affffffa",
    "#aafffffa",
    "#affffffa",
    "#aafffffa",
    "#affffffa",
    "#aaaaaaaa",
    "#########"
  ]
  readonly property var mapFilm: { "#": "#1a1a2e", "a": "#2d2d44", "f": "#c8c8e0" }

  readonly property var gridChatgpt: [
    ".........",
    "..gggg...",
    ".gwwwwg..",
    ".gwgwwg..",
    "ggwwwwgg.",
    ".gwgwwg..",
    ".gwwwwg..",
    "..gggg...",
    "........."
  ]
  readonly property var mapChatgpt: { "g": "#10a37f", "w": "#ffffff" }

  readonly property var gridPin: [
    "....R....",
    "...RRR...",
    "..RWWWR..",
    ".RWWWWWR.",
    ".RWWWWWR.",
    "..RWWWR..",
    "...RWR...",
    "....R....",
    "....#...."
  ]
  readonly property var mapPin: { "R": "#ea4335", "W": "#ffffff", "#": "#444444" }

  readonly property var gridShare: [
    "....aa...",
    "...a..a..",
    "..a....a.",
    "aaaaaaaaa",
    ".a....a..",
    "..a..a...",
    "...aa....",
    ".........",
    "........."
  ]
  readonly property var mapShare: { "a": "#4dabf7" }

  readonly property var gridShield: [
    "...sss...",
    "..sssss..",
    ".sssssss.",
    ".sswwwss.",
    ".sswwwss.",
    "..sssss..",
    "...sss...",
    "....s....",
    "........."
  ]
  readonly property var mapShield: { "s": "#6d4aff", "w": "#b4a0ff" }

  readonly property var gridRofi: [
    "#########",
    "#o#o#o#o#",
    "#########",
    "#o#o#o#o#",
    "#########",
    "#o#o#o#o#",
    "#########",
    "#o#o#o#o#",
    "#########"
  ]
  readonly property var mapRofi: { "#": "#0a0a0c", "o": "#3ddf6e" }

  readonly property var gridNeovim: [
    "#########",
    "#g.gg.gg#",
    "#gGg.gGg#",
    "#gGgggGg#",
    "#gggGggg#",
    "#gGg.gGg#",
    "#g.gg.gg#",
    "#ggggggg#",
    "#########"
  ]
  readonly property var mapNeovim: { "#": "#0a2a1a", "g": "#57a64e", "G": "#8fe87f" }

  readonly property var gridDisk: [
    ".........",
    "..#####..",
    ".#ooooo#.",
    "#oo###oo#",
    "#o#...#o#",
    "#oo###oo#",
    ".#ooooo#.",
    "..#####..",
    "........."
  ]
  readonly property var mapDisk: { "#": "#1a1a22", "o": "#6a6a80" }

  readonly property var gridMoon: [
    ".........",
    "..mmm....",
    ".mmmmm...",
    "mmmmm....",
    "mmmmm....",
    ".mmmmm...",
    "..mmm....",
    ".........",
    "........."
  ]
  readonly property var mapMoon: { "m": "#ffe066" }

  readonly property var gridPen: [
    "........p",
    ".......pp",
    "......pp.",
    ".....pp..",
    "....pp...",
    "...pp....",
    "..pp.....",
    ".pp......",
    "p........"
  ]
  readonly property var mapPen: { "p": "#f7b32b" }

  readonly property var gridChart: [
    "#########",
    "#ggggggg#",
    "#ggggggg#",
    "#g#gg#g##",
    "#g#gg#g##",
    "#g#g#g###",
    "#g#g#g###",
    "#ggggggg#",
    "#########"
  ]
  readonly property var mapChart: { "#": "#0a0a0c", "g": "#3ddf6e" }

  readonly property var gridPrinter: [
    ".........",
    "..wwwww..",
    ".ppppppp.",
    "pPpppppPp",
    "pPpppppPp",
    ".ppppppp.",
    "..wWWWw..",
    "..wWWWw..",
    "........."
  ]
  readonly property var mapPrinter: { "p": "#6a6a78", "P": "#3a3a48", "w": "#ffffff", "W": "#e0e0e8" }

  readonly property var gridClipboard: [
    "..#####..",
    ".#ccccc#.",
    "#cwwwwwc#",
    "#cwwwwwc#",
    "#cwwwwwc#",
    "#cwwwwwc#",
    "#cwwwwwc#",
    "#ccccccc#",
    "#########"
  ]
  readonly property var mapClipboard: { "#": "#8a7340", "c": "#c4a35a", "w": "#fff8e0" }

  readonly property var gridEmoji: [
    ".........",
    "..yyyyy..",
    ".ywwwwwy.",
    "ywWwwwWwy",
    "ywwwwwwwy",
    "ywWwwWWwy",
    ".ywwwwwy.",
    "..yyyyy..",
    "........."
  ]
  readonly property var mapEmoji: { "y": "#ffd43b", "w": "#fff3bf", "W": "#5c3d00" }

  readonly property var gridPalette: [
    "#########",
    "#ppppppp#",
    "#prgbywp#",
    "#pwwwwwp#",
    "#pwcocwp#",
    "#pwwwwwp#",
    "#ppppppp#",
    "#########",
    "#########"
  ]
  readonly property var mapPalette: { "#": "#2a2a35", "p": "#4a4a58", "r": "#ff6b6b", "g": "#51cf66", "b": "#4dabf7", "y": "#ffd43b", "w": "#f1f3f5", "c": "#22b8cf", "o": "#ff922b" }

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

  readonly property int menuGridX: pad
  readonly property int menuGridY: 28 + tabH
  readonly property int menuCols: 9
  readonly property int menuRowsMax: 5

  function hitMenuSlot(px, py) {
    if (selectedTab < 0) return -1
    if (root.menuTabs[selectedTab].route === "apps") {
      // apps: same grid geometry over appRows
    }
    var y0 = menuGridY
    var x0 = menuGridX
    if (px < x0 || py < y0) return -1
    var col = Math.floor((px - x0) / pitch)
    var row = Math.floor((py - y0) / pitch)
    if (col < 0 || col >= menuCols || row < 0 || row >= menuRowsMax) return -1
    if (px >= x0 + col * pitch + slot || py >= y0 + row * pitch + slot) {
      // allow full pitch cell for hover feel; only reject past end of slot slightly
    }
    var count = (root.menuTabs[selectedTab].route === "apps")
      ? root.appRows.length : root.menuItems().length
    var idx = row * menuCols + col
    return (idx >= 0 && idx < count) ? idx : -1
  }

  function menuSlotOrigin(i) {
    var col = i % menuCols
    var row = Math.floor(i / menuCols)
    return { x: menuGridX + col * pitch, y: menuGridY + row * pitch }
  }

  function menuSlotLabel(i) {
    if (root.menuTabs[selectedTab].route === "apps") {
      var a = root.appRows[i]
      return a ? a.name : ""
    }
    var it = root.menuItemAt(i)
    return it ? String(it[1] || "") : ""
  }

  function hitSlot(px, py) {
    if (selectedTab >= 0) return -1
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
            var ti = root.hitTab(bx, by)
            root.hoveredTab = ti
            var i = -1
            var label = ""
            var origin = null
            if (ti >= 0) {
              i = -1
              var t = root.menuTabs[ti]
              label = t ? t.label : ""
              origin = { x: bx, y: 0 }
            } else if (root.selectedTab >= 0) {
              i = root.hitMenuSlot(bx, by)
              label = (i >= 0) ? root.menuSlotLabel(i) : ""
              origin = (i >= 0) ? root.menuSlotOrigin(i) : null
            } else {
              i = root.hitSlot(bx, by)
              if (i >= 0) {
                var it = root.slots[i]
                label = it ? it.name : ""
                origin = root.slotOrigin(i)
              }
            }
            root.hoveredSlot = i
            if (label && origin) {
              root.showTip(label, panel.ox + (origin.x + 8) * panel.s, panel.oy + origin.y * panel.s - 4 * panel.s)
            } else {
              root.hideTip()
            }
          }
          onExited: {
            root.hoveredTab = -1
            root.hideTip()
          }
          onClicked: function(mouse) {
            var bx = mouse.x / panel.s
            var by = mouse.y / panel.s
            var ti = root.hitTab(bx, by)
            if (ti >= 0) {
              root.openTab(ti)
              return
            }
            if (root.selectedTab >= 0) {
              var mi = root.hitMenuSlot(bx, by)
              if (mi >= 0) {
                if (root.menuTabs[root.selectedTab].route === "apps") {
                  var a = root.appRows[mi]
                  if (a) {
                    root.launchApp(a)
                    root.close()
                  }
                } else {
                  root.launchMenuItem(mi)
                }
                return
              }
              // Back affordance: click header row under tabs
              if (by >= root.tabH && by < root.tabH + 14 && root.goBackMenu())
                return
              return
            }
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

            // Title — shows selected tab label + glyph when a menu tab is active
            ctx.fillStyle = "#404040"
            ctx.font = "bold " + String(8 * s) + "px Monocraft, monospace"
            ctx.textAlign = "left"
            ctx.textBaseline = "top"
            if (root.selectedTab >= 0) {
              var activeTab = root.menuTabs[root.selectedTab]
              ctx.fillText(activeTab.icon + "  " + root.menuTitle(), root.pad * s, root.titleY * s)
            } else {
              ctx.fillText("Inventory", root.pad * s, root.titleY * s)
            }

            // Omarchy menu tabs (top strip) — glyph icons; selected = greyed
            var n = root.menuTabs.length
            var gap = 1
            var tw = (root.panelW - 4 - gap * (n - 1)) / n
            for (var t = 0; t < n; t++) {
              var tx = (2 + t * (tw + gap)) * s
              var ty = 2 * s
              var tww = tw * s
              var thh = (root.tabH - 4) * s
              var hot = root.hoveredTab === t
              var selected = Number(root.selectedTab) === t
              if (selected) {
                // Greyed-out to denote in use
                ctx.fillStyle = hot ? "#6a6a6a" : "#5a5a5a"
              } else {
                ctx.fillStyle = hot ? "#b0b0b0" : "#8b8b8b"
              }
              ctx.fillRect(tx, ty, tww, thh)
              ctx.fillStyle = selected ? "#2a2a2a" : "#373737"
              ctx.fillRect(tx, ty, tww, s)
              ctx.fillRect(tx, ty, s, thh)
              ctx.fillStyle = selected ? "#888888" : "#ffffff"
              ctx.fillRect(tx, ty + thh - s, tww, s)
              ctx.fillRect(tx + tww - s, ty, s, thh)
              ctx.fillStyle = selected ? "#c0c0c0" : (hot ? "#ffffff" : "#202020")
              ctx.font = "bold " + String(6 * s) + "px Symbols Nerd Font, Monocraft, monospace"
              ctx.textAlign = "center"
              ctx.textBaseline = "middle"
              ctx.fillText(root.menuTabs[t].icon, tx + tww / 2, ty + thh / 2)
            }
            ctx.textAlign = "left"
            ctx.textBaseline = "top"

            // When a tab is selected, draw its menu list instead of classic slots
            if (root.selectedTab >= 0) {
              drawMenuView(ctx, s)
              return
            }

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
              } else if (it.name) {
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText(it.name.charAt(0).toUpperCase(), (o.x + sz / 2) * s, (o.y + sz / 2) * s)
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
              }
            }
          }

          function drawMenuView(ctx, s) {
            var isApps = root.menuTabs[root.selectedTab].route === "apps"
            var items = isApps ? root.appRows : root.menuItems()
            var count = items.length

            // Back chip when drilled into a submenu
            if (root.menuPath.length > 0) {
              ctx.fillStyle = "#6a6a6a"
              ctx.fillRect(root.pad * s, (root.tabH + 4) * s, 28 * s, 10 * s)
              ctx.fillStyle = "#ffffff"
              ctx.font = "bold " + String(6 * s) + "px Monocraft, monospace"
              ctx.textAlign = "left"
              ctx.textBaseline = "middle"
              ctx.fillText("\u2190 Back", (root.pad + 3) * s, (root.tabH + 9) * s)
            }

            var y0 = root.menuGridY
            var x0 = root.menuGridX
            var maxShow = root.menuCols * root.menuRowsMax

            if (count === 0) {
              ctx.fillStyle = "#505050"
              ctx.font = String(7 * s) + "px Monocraft, monospace"
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
              var msg = isApps ? (root.appRows.length === 0 ? "No apps found" : "Loading apps...")
                             : "No items"
              ctx.fillText(msg, x0 * s, (y0 + 8) * s)
              return
            }

            var show = Math.min(count, maxShow)
            for (var i = 0; i < show; i++) {
              var o = root.menuSlotOrigin(i)
              drawSlotFrame(ctx, o.x * s, o.y * s, root.slot * s, s, false)
              if (i === root.hoveredSlot) {
                ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                ctx.fillRect(o.x * s, o.y * s, root.slot * s, root.slot * s)
              }

              if (isApps) {
                // Letter tile fallback for apps (icons via shell API not drawn on canvas)
                var a = root.appRows[i]
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                var ch = a && a.name ? a.name.charAt(0).toUpperCase() : "?"
                ctx.fillText(ch, (o.x + root.slot / 2) * s, (o.y + root.slot / 2) * s)
              } else {
                var it = root.menuItemAt(i)
                if (it && it[0]) {
                  // Glyph icon from omarchy menu
                  ctx.fillStyle = "#202020"
                  ctx.font = "bold " + String(8 * s) + "px Symbols Nerd Font, Monocraft, monospace"
                  ctx.textAlign = "center"
                  ctx.textBaseline = "middle"
                  ctx.fillText(it[0], (o.x + root.slot / 2) * s, (o.y + root.slot / 2) * s)
                } else if (it && it[1]) {
                  ctx.fillStyle = "#e8e8f0"
                  ctx.font = "bold " + String(6 * s) + "px Monocraft, monospace"
                  ctx.textAlign = "center"
                  ctx.textBaseline = "middle"
                  ctx.fillText(String(it[1]).charAt(0).toUpperCase(), (o.x + root.slot / 2) * s, (o.y + root.slot / 2) * s)
                }
                // Folder / has-children marker
                if (it && it[4] && it[4].length) {
                  ctx.fillStyle = "#ffd43b"
                  ctx.fillRect((o.x + root.slot - 5) * s, (o.y + root.slot - 5) * s, 3 * s, 3 * s)
                }
              }
            }

            // Truncation note
            if (count > show) {
              ctx.fillStyle = "#505050"
              ctx.font = String(6 * s) + "px Monocraft, monospace"
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
              ctx.fillText("+" + (count - show) + " more", x0 * s, (y0 + root.menuRowsMax * root.pitch + 4) * s)
            }

            ctx.textAlign = "left"
            ctx.textBaseline = "top"
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
