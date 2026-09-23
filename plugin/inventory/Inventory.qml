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

  // Drop the inventory Overlay while About (a normal window) is open so
  // About paints in front; restore Overlay when About closes.
  property bool aboutOpen: false
  property bool aboutSeen: false
  function launchAbout() {
    Quickshell.execDetached(["omarchy-launch-about"])
    aboutOpen = true
    aboutSeen = false
    aboutPoll.restart()
  }
  Timer {
    id: aboutPoll
    interval: 350
    repeat: true
    onTriggered: aboutClients.running = false, aboutClients.running = true
  }
  Process {
    id: aboutClients
    running: false
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onTextChanged: {
        var open = false
        try {
          var cs = JSON.parse(text)
          for (var i = 0; i < cs.length; i++) {
            if (String(cs[i].class || "") === "org.omarchy.about") { open = true; break }
          }
        } catch (e) {}
        if (open) {
          root.aboutSeen = true
          root.aboutOpen = true
        } else if (root.aboutSeen) {
          root.aboutOpen = false
          aboutPoll.stop()
        }
        // else: About not mapped yet — keep polling until it appears.
      }
    }
  }
  onAboutOpenChanged: { if (invCanvas) invCanvas.requestPaint() }

  // Session metrics for armor progression (hours since Hyprland came up,
  // live window count, installed .desktop count).
  property int metricHours: 0
  property int metricWins: 0
  function refreshMetrics() {
    hoursProc.running = false
    hoursProc.running = true
    winsProc.running = false
    winsProc.running = true
  }
  Process {
    id: hoursProc
    running: false
    command: ["python3", "-c",
      "import os,glob,time; r=os.environ.get('XDG_RUNTIME_DIR','/run/user/'+str(os.getuid())); d=sorted(glob.glob(r+'/hypr/*')); print(int((time.time()-os.stat(d[0]).st_ctime)//3600) if d else 0)"]
    stdout: StdioCollector {
      onTextChanged: {
        var h = parseInt(String(text).trim(), 10)
        if (isFinite(h) && h >= 0) {
          root.metricHours = h
          root.maybeArmorAchievement()
          if (invCanvas) invCanvas.requestPaint()
        }
      }
    }
  }
  Process {
    id: winsProc
    running: false
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onTextChanged: {
        try {
          var n = JSON.parse(text).length
          if (isFinite(n)) {
            root.metricWins = n
            root.maybeArmorAchievement()
            if (invCanvas) invCanvas.requestPaint()
          }
        } catch (e) {}
      }
    }
  }
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
    refreshMetrics()
    maybeArmorAchievement()
    // Re-sync hotbar from disk in case HUD/inventory drifted.
    hotbarFile.reload()
  }
  function close() {
    opened = false
    selectedTab = -1
    menuPath = []
    hoveredSlot = -1
    contextSlot = -1
    pinnedSlot = -1
    steveCrouching = false
    clearDrag()
    hideTip()
  }
  // IPC probe for toggle scripts (FLAG files desync across shell restarts).
  function status() { return opened ? "open" : "closed" }

  property int guiScale: 2
  property int hoveredSlot: -1
  property string tipText: ""
  property real tipX: 0
  property real tipY: 0
  property bool tipVisible: false

  // F3 debug overlay + creeper/empty-hotbar key eggs (classic + tabs).
  property bool debugOverlay: false
  property string keyBuf: ""
  // Steve sneaks while this is true (toggle by clicking his preview well).
  property bool steveCrouching: false
  onSteveCrouchingChanged: { if (opened && invCanvas) invCanvas.requestPaint() }
  Timer {
    id: keyBufClear
    interval: 1200
    onTriggered: root.keyBuf = ""
  }
  function handleInventoryKey(ev) {
    var k = ev.key
    var t = ev.text || ""
    // F3 — toggle debug metrics overlay.
    if (k === Qt.Key_F3) {
      debugOverlay = !debugOverlay
      if (invCanvas) invCanvas.requestPaint()
      ev.accepted = true
      return
    }
    // Q — classic MC drop. Empty inventory just laughs at you.
    if (k === Qt.Key_Q && (ev.modifiers & Qt.AltModifier) === 0) {
      Quickshell.execDetached([
        Quickshell.env("HOME") + "/.local/bin/minecraft-toast",
        "You threw nothing",
        "There is nothing in your hand"
      ])
      ev.accepted = true
      return
    }
    // Type "creeper" for the classic AW MAN.
    if (t.length === 1 && /[a-z]/i.test(t)) {
      keyBuf = (keyBuf + t.toLowerCase()).slice(-7)
      keyBufClear.restart()
      if (keyBuf === "creeper") {
        keyBuf = ""
        Quickshell.execDetached([
          Quickshell.env("HOME") + "/.local/bin/minecraft-toast",
          "Aww man...",
          "Creeper? Aw man"
        ])
        ev.accepted = true
        return
      }
    }
  }

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
    // Official About (menu-data stores no action for this leaf).
    if (menuTabs[selectedTab] && menuTabs[selectedTab].route === "about"
        && action.length === 0) {
      root.launchAbout()
      return
    }
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

  // Right-side back chip geometry (base units) — sits on the title row, right edge.
  readonly property int backChipW: 34
  readonly property int backChipH: 11
  readonly property int backChipX: panelW - pad - backChipW
  readonly property int backChipY: titleY - 1
  function hitBack(px, py) {
    if (menuPath.length <= 0) return false
    return px >= backChipX && px < backChipX + backChipW
        && py >= backChipY && py < backChipY + backChipH
  }

  // (launchAbout lives near the top — opens official About and lowers layer.)

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
          sub: String(e.genericName || ""),
          icon: String(e.icon || ""),
          iconUrl: root.resolveAppIcon(e.icon)
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
      syncSlotIcons()
      maybeArmorAchievement()
      if (opened && invCanvas) invCanvas.requestPaint()
    } catch (err) {}
  }

  // Omarchy system icon (AppLibrary index → themed iconPath fallback).
  function resolveAppIcon(icon) {
    var value = String(icon || "")
    if (!value.length) return ""
    try {
      if (appLibrary && typeof appLibrary.iconSource === "function") {
        var src = String(appLibrary.iconSource(value) || "")
        if (src.length) return src
      }
    } catch (e) {}
    try {
      var p = Quickshell.iconPath(value, true)
      if (p && p.length) return p
    } catch (e2) {}
    return ""
  }

  // Existing inventory pixel sprites, matched by desktop entry name.
  function appSpriteFor(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("libreoffice writer") >= 0 || n.indexOf("omawrite") >= 0)
      return { rows: root.gridWriter, colors: root.mapWriter }
    if (n.indexOf("libreoffice calc") >= 0 || n.indexOf("omacalc") >= 0)
      return { rows: root.gridCalc, colors: root.mapCalc }
    if (n.indexOf("libreoffice impress") >= 0)
      return { rows: root.gridImpress, colors: root.mapImpress }
    if (n.indexOf("docker") >= 0)
      return { rows: root.gridDocker, colors: root.mapDocker }
    if (n.indexOf("btop") >= 0 || n.indexOf("system monitor") >= 0)
      return { rows: root.gridBtop, colors: root.mapBtop }
    if (n.indexOf("obs") >= 0 || n.indexOf("obsidian") >= 0)
      return n.indexOf("obsidian") >= 0
        ? { rows: root.gridObsidian, colors: root.mapObsidian }
        : { rows: root.gridObs, colors: root.mapObs }
    if (n.indexOf("inkscape") >= 0)
      return { rows: root.gridInkscape, colors: root.mapInkscape }
    if (n.indexOf("pinta") >= 0)
      return { rows: root.gridPinta, colors: root.mapPinta }
    if (n.indexOf("evince") >= 0 || n.indexOf("document viewer") >= 0 || n.indexOf("pdf") >= 0)
      return { rows: root.gridPdf, colors: root.mapPdf }
    if (n === "mpv" || n.indexOf("mpv media") >= 0)
      return { rows: root.gridPlay, colors: root.mapPlay }
    if (n.indexOf("imv") >= 0)
      return { rows: root.gridImage, colors: root.mapImage }
    if (n.indexOf("kdenlive") >= 0)
      return { rows: root.gridFilm, colors: root.mapFilm }
    if (n.indexOf("chatgpt") >= 0)
      return { rows: root.gridChatgpt, colors: root.mapChatgpt }
    if (n.indexOf("localsend") >= 0)
      return { rows: root.gridShare, colors: root.mapShare }
    if (n.indexOf("proton vpn") >= 0)
      return { rows: root.gridShield, colors: root.mapShield }
    if (n.indexOf("rofi") >= 0)
      return { rows: root.gridRofi, colors: root.mapRofi }
    if (n.indexOf("neovim") >= 0 || n === "nvim")
      return { rows: root.gridNeovim, colors: root.mapNeovim }
    if (n.indexOf("disks") >= 0 || n.indexOf("disk utility") >= 0)
      return { rows: root.gridDisk, colors: root.mapDisk }
    if (n.indexOf("moonlight") >= 0)
      return { rows: root.gridMoon, colors: root.mapMoon }
    if (n.indexOf("xournal") >= 0)
      return { rows: root.gridPen, colors: root.mapPen }
    if (n.indexOf("files") >= 0 || n.indexOf("nautilus") >= 0)
      return { rows: root.gridFiles, colors: root.mapFiles }
    if (n.indexOf("brave") >= 0)
      return { rows: root.gridBrave, colors: root.mapBrave }
    if (n.indexOf("terminal") >= 0 || n.indexOf("foot") >= 0)
      return { rows: root.gridTerminal, colors: root.mapTerminal }
    if (n.indexOf("youtube") >= 0)
      return { rows: root.gridYoutube, colors: root.mapYoutube }
    if (n.indexOf("proton mail") >= 0)
      return { rows: root.gridProton, colors: root.mapProton }
    if (n.indexOf("google maps") >= 0)
      return { rows: root.gridPin, colors: root.mapPin }
    if (n.indexOf("clipboard") >= 0)
      return { rows: root.gridClipboard, colors: root.mapClipboard }
    if (n.indexOf("emoji") >= 0)
      return { rows: root.gridEmoji, colors: root.mapEmoji }
    if (n.indexOf("theme") >= 0 || n.indexOf("palette") >= 0)
      return { rows: root.gridPalette, colors: root.mapPalette }
    if (n.indexOf("printer") >= 0 || n.indexOf("printing") >= 0)
      return { rows: root.gridPrinter, colors: root.mapPrinter }
    if (n.indexOf("chatgpt") >= 0 || n.indexOf("openai") >= 0)
      return { rows: root.gridChatgpt, colors: root.mapChatgpt }
    return null
  }

  // System icon bitmaps for canvas (cached Image objects; repaint when ready).
  property var appIconCache: ({})
  Component {
    id: appIconComp
    Image {
      asynchronous: true
      smooth: false
      mipmap: false
      visible: false
      sourceSize: Qt.size(48, 48)
      onStatusChanged: {
        // Repaint on Ready OR Error so sprite/letter fallbacks can show.
        if (invCanvas && (status === Image.Ready || status === Image.Error))
          invCanvas.requestPaint()
      }
    }
  }
  function appIconImage(url) {
    if (!url || !url.length) return null
    var img = appIconCache[url]
    if (img) return img
    img = appIconComp.createObject(root, { source: url })
    if (img) appIconCache[url] = img
    return img
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

  function launchArmorWell(w) {
    var it = armorWellItem(w)
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
  readonly property int craftSlot: 16
  readonly property int craftPitch: 18
  readonly property int armorCols: 1

  // y layout (base): tabs 0..tabH, then classic layout shifted by tabH
  readonly property int tabH: 14
  readonly property int titleY: 6 + tabH
  readonly property int topY: 16 + tabH
  readonly property int craftX: 86
  readonly property int craftResultX: 136
  readonly property int craftY: 18 + tabH
  // Left column: 4 armor/clothing wells matching the taller character box.
  readonly property int armorX: 8
  readonly property int armorY: 18 + tabH
  readonly property int armorSlot: 16
  readonly property int armorGap: 4
  readonly property int armorColH: 4 * armorSlot + 3 * armorGap
  // Bigger character box, same height as the armor column.
  readonly property int playerX: 30
  readonly property int playerY: 18 + tabH
  readonly property int playerW: 44
  readonly property int playerH: armorColH
  // Extra gap under player/craft so the armor note fits without overlapping.
  readonly property int mainY: 118 + tabH
  readonly property int panelW: 176
  // Note band: just below the player/armor column, above the main grid.
  readonly property int noteY: armorY + armorColH + 4
  readonly property int noteCx: Math.floor(panelW / 2)

  // Click target: the tall player-preview well (crouch toggle).
  function hitPlayer(px, py) {
    return px >= playerX && px < playerX + playerW
        && py >= playerY && py < playerY + playerH
  }

  // System icon URLs for classic main/hotbar slots (avoids chunky 9×9 art
  // when a matching desktop entry icon exists). Keyed by slot index.
  property var slotIconUrls: ({})
  function findAppIconUrl(name) {
    var n = String(name || "").toLowerCase()
    if (!n.length) return ""
    var best = ""
    for (var j = 0; j < appRows.length; j++) {
      var a = appRows[j]
      if (!a || !a.iconUrl) continue
      var an = String(a.name || "").toLowerCase()
      if (!an.length) continue
      if (an === n) return a.iconUrl
      if (!best && (an.indexOf(n) >= 0 || n.indexOf(an) >= 0))
        best = a.iconUrl
    }
    return best
  }
  function syncSlotIcons() {
    var m = {}
    for (var i = 0; i < slotCount; i++) {
      var it = slots[i]
      if (!it || !it.name) continue
      if (it.iconUrl) { m[i] = it.iconUrl; continue }
      var u = findAppIconUrl(it.name)
      if (u) m[i] = u
    }
    slotIconUrls = m
    if (opened && invCanvas) invCanvas.requestPaint()
  }

  // Menu grid rows for the open tab — expand the panel so every item fits
  // (no "+N more" truncation). Cap keeps the panel on a 768px screen.
  readonly property int menuItemCount: {
    if (selectedTab < 0) return 0
    return (menuTabs[selectedTab].route === "apps") ? appRows.length : menuItems().length
  }
  readonly property int menuRowsShow: selectedTab < 0 ? 0
    : Math.min(15, Math.max(1, Math.ceil(menuItemCount / menuCols)))

  // Hotbar sits below the menu grid when a tab is open (panel grows to fit).
  readonly property int hotbarY: {
    if (selectedTab >= 0) {
      var needed = 28 + tabH + menuRowsShow * pitch + 4
      return Math.max(mainY + mainRows * pitch + 4, needed)
    }
    return mainY + mainRows * pitch + 4
  }
  readonly property int panelH: hotbarY + pitch + pad

  // Selection state for smart armor-box suggestions (classic view).
  property int contextSlot: -1
  // Sticky suggestion source when a slot is clicked (survives hover leave).
  property int pinnedSlot: -1
  onContextSlotChanged: { if (opened && invCanvas) invCanvas.requestPaint() }
  onPinnedSlotChanged: { if (opened && invCanvas) invCanvas.requestPaint() }

  // Active suggestion source: live hover wins, then sticky pin.
  readonly property int suggestSrc: contextSlot >= 0 ? contextSlot : pinnedSlot

  // Related apps/services for a selected launcher (max 4 → armor wells).
  function suggestionsFor(i) {
    if (i < 0 || i >= slotCount) return []
    var it = slots[i]
    if (!it || !it.cmd || !it.cmd.length) return []
    var n = String(it.name || "").toLowerCase()
    var out = []
    function add(idx) {
      if (idx === i) return
      var s = slots[idx]
      if (s && s.cmd && s.cmd.length && out.indexOf(s) < 0) out.push(s)
    }
    function byName(name) {
      for (var k = 0; k < slotCount; k++) {
        if (slots[k] && slots[k].name === name) return k
      }
      return -1
    }
    function addName(name) { add(byName(name)) }

    if (/libreoffice|writer|calc|impress|pdf|evince/.test(n)) {
      addName("LibreOffice Writer"); addName("LibreOffice Calc")
      addName("LibreOffice Impress"); addName("Evince (PDF)")
      addName("File manager"); addName("Neovim")
    } else if (/terminal|btop|docker|neovim|nvim|monitor|system/.test(n)) {
      addName("Terminal"); addName("btop"); addName("Docker")
      addName("Neovim"); addName("System monitor"); addName("File manager")
    } else if (/obsidian|note|chatgpt|ink|pinta|xournal|draw|image|imv|inkscape/.test(n)) {
      addName("Obsidian"); addName("ChatGPT"); addName("Inkscape")
      addName("Pinta"); addName("Xournal++"); addName("imv")
    } else if (/mpv|film|kdenlive|obs|video|play|media|youtube/.test(n)) {
      addName("mpv"); addName("OBS Studio"); addName("Kdenlive")
      addName("imv"); addName("YouTube")
    } else if (/brave|browser|search|web|x\.com|yakihonne|mail|maps|proton/.test(n)) {
      addName("Brave Search"); addName("Google Maps"); addName("Proton Mail")
      addName("X"); addName("Yakihonne"); addName("YouTube")
    } else if (/file|folder|disk|printer|copy|share|local/.test(n)) {
      addName("File manager"); addName("Disks"); addName("Printer")
      addName("LocalSend"); addName("Clipboard")
    } else if (/vpn|proton vpn|shield|security/.test(n)) {
      addName("Proton VPN"); addName("Proton Mail"); addName("Brave Search")
      addName("Clipboard")
    } else {
      // Generic productivity fallbacks
      addName("Terminal"); addName("File manager")
      addName("Clipboard"); addName("Theme menu")
      addName("Emoji picker"); addName("Rofi launcher")
    }
    return out.slice(0, 4)
  }

  // Left column (armor wells 0..3): Steve's clothes/hair, recolored by tier.
  // Smart suggestions live in the right-side craft wells instead.
  function armorWellItem(w) {
    return slots[armorBase + w]
  }

  // Armor material tier from time on device + live activity + installed apps.
  // Cloth → Wood → Chain → Iron → Diamond → Netherite.
  // score = apps + 2×session-hours + 3×open-windows (all three grow with use).
  // Thresholds: Wood 50, Chain 100, Iron 160, Diamond 220, Netherite 300.
  // Metrics refresh on open() + appRefreshTimer so tiers move over time.
  function armorTier() {
    var apps = appRows.length
    var hours = Math.max(0, metricHours | 0)
    var wins = Math.max(0, metricWins | 0)
    var score = apps + hours * 2 + wins * 3
    var name = "Cloth", tone = 0
    if (score >= 300) { name = "Netherite"; tone = 5 }
    else if (score >= 220) { name = "Diamond"; tone = 4 }
    else if (score >= 160) { name = "Iron"; tone = 3 }
    else if (score >= 100) { name = "Chain"; tone = 2 }
    else if (score >= 50) { name = "Wood"; tone = 1 }
    return {
      name: name, tone: tone, count: apps, score: score,
      hours: hours, wins: wins
    }
  }
  // Next tier threshold for progress bar / enchant glint (null = maxed).
  function armorNextThreshold(tone) {
    if (tone <= 0) return 50
    if (tone === 1) return 100
    if (tone === 2) return 160
    if (tone === 3) return 220
    if (tone === 4) return 300
    return null
  }
  function armorPrevThreshold(tone) {
    if (tone <= 0) return 0
    if (tone === 1) return 50
    if (tone === 2) return 100
    if (tone === 3) return 160
    if (tone === 4) return 220
    return 300
  }
  // Achievement toast when the armor tier levels up (milestone).
  // Netherite unlock also fires a brief beacon-beam flash on the classic view.
  property int lastArmorTone: -1
  property real beaconUntil: 0
  function maybeArmorAchievement() {
    var t = armorTier()
    if (lastArmorTone < 0) { lastArmorTone = t.tone; return }
    if (t.tone > lastArmorTone) {
      lastArmorTone = t.tone
      if (t.tone >= 5) {
        beaconUntil = Date.now() + 3500
        beaconTimer.restart()
      }
      Quickshell.execDetached([
        Quickshell.env("HOME") + "/.local/bin/minecraft-toast",
        "Advancement Made!",
        "Armor upgraded to " + t.name
      ])
    } else if (t.tone < lastArmorTone) {
      lastArmorTone = t.tone
    }
  }
  Timer {
    id: beaconTimer
    interval: 200
    repeat: true
    onTriggered: {
      if (Date.now() >= root.beaconUntil) stop()
      if (root.opened && root.invCanvas) root.invCanvas.requestPaint()
    }
  }
  // Material palette for armor icons: [main, dark, accent]
  // High contrast against the #8b8b8b slot background.
  readonly property var armorTierPalettes: [
    ["#8ecff0", "#5a9ec9", "#4a3fa0"], // Cloth (unused — tone 0 keeps Steve maps)
    ["#8b5a2b", "#6b4420", "#5a3a1a"], // Wood
    ["#5f6f8a", "#3d4a60", "#4a5870"], // Chain (steel blue-gray)
    ["#e8e8e8", "#909090", "#b8b8b8"], // Iron
    ["#5decd7", "#1f8f82", "#3ab8a8"], // Diamond
    ["#3d3540", "#1a151c", "#2a2230"]  // Netherite (dark purple-gray)
  ]
  // Recolor a clothing grid's map for the current armor tier.
  // Cloth (tone 0) returns the map unchanged — Steve's clothes as authored.
  function armorPaletteFor(map) {
    var tone = armorTier().tone
    if (tone === 0) return map
    var pal = armorTierPalettes[tone]
    var out = {}
    for (var k in map) {
      out[k] = map[k]
    }
    // Garment keys used by hair/shirt/trousers/shoes art.
    if (out["c"] !== undefined) { out["c"] = pal[0]; out["C"] = pal[1] }
    if (out["p"] !== undefined) { out["p"] = pal[0] }
    if (out["b"] !== undefined) { out["b"] = pal[2] }
    // Hair → helm shell; face covered (metal) from chain upward.
    if (out["h"] !== undefined) {
      out["h"] = pal[1]
      if (tone >= 2 && out["s"] !== undefined) out["s"] = pal[0]
    }
    return out
  }

  // Right-side craft wells (4..7) + result (8): smart suggestions.
  // Result shows the hovered/pinned source app; arrow points at it.
  function craftWellItem(i) {
    if (i === resultIdx) {
      var src = suggestSrc
      return src >= 0 ? slots[src] : null
    }
    var sug = suggestionsFor(suggestSrc)
    var w = i - craftBase
    return (w >= 0 && w < sug.length) ? sug[w] : null
  }
  function launchCraftWell(i) {
    var it = craftWellItem(i)
    if (it && it.cmd && it.cmd.length)
      Quickshell.execDetached(it.cmd)
  }
  // Unified display item for tooltips / icon drawing.
  function slotDisplayItem(i) {
    if (i >= armorBase && i < armorBase + 4) return armorWellItem(i)
    if (i >= craftBase && i <= resultIdx) return craftWellItem(i)
    return slots[i]
  }

  // Drag & drop: classic slot↔slot, plus menu/app → hotbar from any tab.
  property int dragFrom: -1
  property int dragMenuFrom: -1
  property var dragPayload: null
  property bool dragging: false
  property real dragX: 0
  property real dragY: 0

  function clearDrag() {
    dragFrom = -1
    dragMenuFrom = -1
    dragPayload = null
    dragging = false
  }

  // Particle crits on a successful menu → hotbar drop.
  property var critParticles: []
  property real critUntil: 0
  function spawnCrits(bx, by) {
    var pts = []
    for (var i = 0; i < 8; i++) {
      var ang = (Math.PI * 2 * i) / 8 + Math.random() * 0.4
      var spd = 20 + Math.random() * 30
      pts.push({
        x: bx, y: by,
        vx: Math.cos(ang) * spd,
        vy: Math.sin(ang) * spd - 15
      })
    }
    critParticles = pts
    critUntil = Date.now() + 450
    critTimer.restart()
    if (invCanvas) invCanvas.requestPaint()
  }
  Timer {
    id: critTimer
    interval: 50
    repeat: true
    onTriggered: {
      if (Date.now() >= root.critUntil) {
        stop()
        root.critParticles = []
      } else {
        var step = 0.05
        var a = root.critParticles
        for (var i = 0; i < a.length; i++) {
          a[i].x += a[i].vx * step
          a[i].y += a[i].vy * step
          a[i].vy += 60 * step
        }
        root.critParticles = a.slice()
      }
      if (root.opened && root.invCanvas) root.invCanvas.requestPaint()
    }
  }

  // Fact rotation + F3 idle repaint while open (classic view keeps the
  // permanent fun fact cycling even when a hover tip is up).
  Timer {
    id: ambientTimer
    interval: 400
    repeat: true
    running: root.opened
    onTriggered: { if (root.invCanvas) root.invCanvas.requestPaint() }
  }

  // Pull async system icons onto the Apps grid as they finish loading.
  Timer {
    id: iconSettleTimer
    interval: 250
    repeat: true
    running: root.opened && root.selectedTab >= 0 &&
      root.menuTabs[root.selectedTab].route === "apps"
    onTriggered: { if (root.invCanvas) root.invCanvas.requestPaint() }
  }

  function beginDrag(i) {
    if (i < mainBase) return
    dragFrom = i
    dragMenuFrom = -1
    dragPayload = null
    dragging = false
  }

  // Start a drag from the active tab's menu/app grid.
  function beginMenuDrag(mi) {
    if (selectedTab < 0 || mi < 0) return
    var payload = menuDragPayload(mi)
    if (!payload) return
    dragFrom = -1
    dragMenuFrom = mi
    dragPayload = payload
    dragging = false
  }

  // Menu leaf / desktop app → hotbar item {name,cmd,rows,colors,iconUrl?}.
  function menuDragPayload(mi) {
    if (selectedTab < 0 || mi < 0) return null
    if (menuTabs[selectedTab].route === "apps") {
      var a = appRows[mi]
      if (!a || !a.id) return null
      var spr = appSpriteFor(a.name)
      return {
        name: a.name,
        cmd: ["uwsm-app", "--", "gtk-launch", a.id + ".desktop"],
        rows: (spr && spr.rows) ? spr.rows : gridGenericApp,
        colors: (spr && spr.colors) ? spr.colors : mapGenericApp,
        iconUrl: a.iconUrl || ""
      }
    }
    var it = menuItemAt(mi)
    if (!it) return null
    var kids = it[4] || []
    if (kids.length > 0) return null
    var action = String(it[2] || "")
    if (!action.length) return null
    var label = String(it[1] || "Item")
    var leafSpr = appSpriteFor(label)
    return {
      name: label,
      cmd: ["bash", "-lc", action],
      rows: (leafSpr && leafSpr.rows) ? leafSpr.rows : gridGenericCmd,
      colors: (leafSpr && leafSpr.colors) ? leafSpr.colors : mapGenericCmd,
      glyph: String(it[0] || "")
    }
  }

  function moveDrag(bx, by) {
    if (dragFrom < 0 && dragMenuFrom < 0) return
    if (!dragging) {
      var o = (dragMenuFrom >= 0) ? menuSlotOrigin(dragMenuFrom) : slotOrigin(dragFrom)
      var dx = bx - (o.x + slot / 2)
      var dy = by - (o.y + slot / 2)
      if (dx * dx + dy * dy > 9) dragging = true
    }
    if (dragging) {
      dragX = bx
      dragY = by
      if (invCanvas) invCanvas.requestPaint()
    }
  }

  function endDrag(bx, by) {
    var menuFrom = dragMenuFrom
    var payload = dragPayload
    if (dragFrom < 0 && menuFrom < 0) return false
    var from = dragFrom
    var wasDrag = dragging
    clearDrag()
    if (invCanvas) invCanvas.requestPaint()
    if (!wasDrag) return false

    var to = hitSlot(bx, by)

    // Menu/app → hotbar drop (only the hotbar strip is a valid target on tabs).
    if (menuFrom >= 0) {
      if (payload && to >= hotbarBase && to < hotbarBase + 9) {
        var ma = slots
        ma[to] = payload
        slots = ma
        saveHotbar()
        hideTip()
        var dro = slotOrigin(to)
        spawnCrits(dro.x + slot / 2, dro.y + slot / 2)
        if (invCanvas) invCanvas.requestPaint()
      }
      return true
    }

    if (to < mainBase || to === from) return true
    // Swap contents (hotbar ↔ main or main ↔ main).
    var a = slots
    var tmp = a[from]
    a[from] = a[to]
    a[to] = tmp
    slots = a
    saveHotbar()
    hideTip()
    if (invCanvas) invCanvas.requestPaint()
    return true
  }

  // Persist the full hotbar row (slots 36-44) so the HUD can follow any item,
  // including ones dragged in from main storage (not just the default nine).
  FileView {
    id: hotbarFile
    path: Quickshell.env("HOME") + "/.config/minecraft_theme/hotbar.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var o = JSON.parse(text())
        if (o && o.items && o.items.length === 9) applyHotbarItems(o.items)
        else if (o && o.order && o.order.length === 9) applyHotbarOrder(o.order)
      } catch (e) {}
    }
    // Another writer (or ourselves after setText) changed the file.
    onFileChanged: reload()
  }
  function saveHotbar() {
    var items = []
    for (var i = 0; i < 9; i++) {
      var it = slots[hotbarBase + i]
      if (it && it.name) {
        var rec = {
          name: it.name,
          cmd: it.cmd || [],
          rows: it.rows || [],
          colors: it.colors || {}
        }
        if (it.iconUrl) rec.iconUrl = it.iconUrl
        if (it.glyph) rec.glyph = it.glyph
        items.push(rec)
      } else {
        items.push(null)
      }
    }
    hotbarFile.setText(JSON.stringify({ items: items }) + "\n")
    hotbarFile.reload()
  }
  function applyHotbarItems(items) {
    if (!items || items.length !== 9) return
    var a = slots
    for (var i = 0; i < 9; i++) {
      var it = items[i]
      if (it && it.name && (it.rows || it.iconUrl || it.glyph))
        a[hotbarBase + i] = it
    }
    slots = a
    if (opened && invCanvas) invCanvas.requestPaint()
  }
  function applyHotbarOrder(names) {
    // Legacy {order:[name]} — resolve against every known launcher, not just
    // the hotbar defaults, so items dragged in from main still match.
    var byName = {}
    var i, it
    for (i = 0; i < slotCount; i++) {
      it = slots[i]
      if (it && it.name && !byName[it.name]) byName[it.name] = it
    }
    var used = {}
    var row = []
    for (i = 0; i < 9; i++) {
      var nm = String(names[i] || "")
      if (byName[nm] && !used[nm]) {
        row.push(byName[nm])
        used[nm] = true
      } else {
        row.push(null)
      }
    }
    // Fill nulls with unused hotbar defaults
    var spare = []
    for (i = hotbarBase; i < hotbarBase + 9; i++) {
      it = slots[i]
      if (it && it.name && !used[it.name]) {
        spare.push(it)
        used[it.name] = true
      }
    }
    for (i = 0; i < 9; i++) {
      if (!row[i] && spare.length) row[i] = spare.shift()
    }
    var a = slots
    for (i = 0; i < 9; i++) a[hotbarBase + i] = row[i]
    slots = a
    if (opened && invCanvas) invCanvas.requestPaint()
  }
  Component.onCompleted: {
    hotbarFile.reload()
    appRefreshTimer.start()
  }

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
    // Official About: menu-data has no children — open Omarchy's About window.
    if (menuTabs[i].route === "about") {
      root.launchAbout()
      return
    }
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
      // Villager "hmm" — soft open sound when browsing a new tab.
      Quickshell.execDetached([
        Quickshell.env("HOME") + "/.local/bin/minecraft-sound", "open"
      ])
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
    ".#pPPPp#.",
    "#pPPPPPp#",
    "#pPPPPPp#",
    "#pPPPPPp#",
    ".#pPPPp#.",
    "..#pPp#.."
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

  // Items placed by index (armor = Steve's clothing; main+hotbar launchers).
  // Hotbar row mirrors HUD order for muscle memory (synced via hotbar.json).
  property var slots: {
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
    // Armor column = Steve's current clothes / hair (piece icons; tier palette
    // recolors them as the armor levels — see armorPaletteFor).
    a[0] = { name: "Hair", cmd: [],
             rows: root.gridClothHelmet, colors: root.mapClothHelmet }
    a[1] = { name: "Shirt", cmd: [],
             rows: root.gridClothChest, colors: root.mapClothChest }
    a[2] = { name: "Trousers", cmd: [],
             rows: root.gridClothLegs, colors: root.mapClothLegs }
    a[3] = { name: "Shoes", cmd: [],
             rows: root.gridClothBoots, colors: root.mapClothBoots }
    return a
  }

  // Steve's clothing / hair piece icons for the 4 left wells (10×10).
  // Base colors match the player preview; armorTierPalettes recolor on level-up.
  readonly property var gridClothHelmet: [
    "..hhhhhh..",
    ".hhhhhhhh.",
    "hhhhhhhhhh",
    "hhhhhhhhhh",
    "hhsssssshh",
    "hsseessehh",
    "hssssssshh",
    ".ssssssssh",
    "..........",
    ".........."
  ]
  readonly property var mapClothHelmet: { "h": "#3a2a1a", "s": "#d4b08a", "e": "#3b5dc9", ".": "#00000000" }

  readonly property var gridClothChest: [
    "..cccccc..",
    ".cCcccccC.",
    "cCccccccCc",
    "cCccccccCc",
    "cccccccccc",
    "cccccccccc",
    "cccccccccc",
    ".cccccccc.",
    ".cccccccc.",
    ".........."
  ]
  readonly property var mapClothChest: { "c": "#8ecff0", "C": "#5a9ec9", ".": "#00000000" }

  readonly property var gridClothLegs: [
    "pppppppppp",
    "pppppppppp",
    "pppppppppp",
    "pppppppppp",
    "pppppppppp",
    "ppp....ppp",
    "ppp....ppp",
    "ppp....ppp",
    "ppp....ppp",
    "ppp....ppp"
  ]
  readonly property var mapClothLegs: { "p": "#4a3fa0", "s": "#3a3080", ".": "#00000000" }

  readonly property var gridClothBoots: [
    "..........",
    "..........",
    "bb.....bb.",
    "bb.....bb.",
    "bbb...bbb.",
    "bbbb.bbbb.",
    "bbbbbbbbb.",
    "bbbbbbbbb.",
    ".bbbbbbbb.",
    ".........."
  ]
  readonly property var mapClothBoots: { "b": "#6b4420", "s": "#4a3010", ".": "#00000000" }

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

  // Fallback art for menu leaves / apps with no brand sprite (need rows+colors
  // so saveHotbar → HUD accepts the dropped item).
  readonly property var gridGenericApp: [
    "#########",
    "#kkkkkkk#",
    "#kwwwwwk#",
    "#kwbbbwk#",
    "#kwbbbwk#",
    "#kwbbbwk#",
    "#kwwwwwk#",
    "#kkkkkkk#",
    "#########"
  ]
  readonly property var mapGenericApp: { "#": "#2a2a35", "k": "#3a3a48", "w": "#c0c0d0", "b": "#5b9bd5" }
  readonly property var gridGenericCmd: [
    "#########",
    "#ppppppp#",
    "#p#####p#",
    "#p#www#p#",
    "#p#wgw#p#",
    "#p#wgw#p#",
    "#p#####p#",
    "#ppppppp#",
    "#########"
  ]
  readonly property var mapGenericCmd: { "#": "#2a2a35", "p": "#8b6914", "w": "#d4b06a", "g": "#51cf66" }

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
      return { x: armorX, y: armorY + (i - armorBase) * (armorSlot + armorGap) }
    if (i >= craftBase && i < craftBase + 4) {
      var cx = (i - craftBase) % 2
      var cy = Math.floor((i - craftBase) / 2)
      return { x: craftX + cx * craftPitch, y: craftY + cy * craftPitch }
    }
    if (i === resultIdx)
      return { x: craftResultX, y: craftY + 9 }
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
    if (col < 0 || col >= menuCols || row < 0 || row >= root.menuRowsShow) return -1
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
    // px, py in base units. Hotbar row stays live on every tab so it can
    // be dragged/launched without leaving the menu view first.
    var lo = (selectedTab >= 0) ? hotbarBase : 0
    var hi = (selectedTab >= 0) ? (hotbarBase + 9) : slotCount
    for (var i = lo; i < hi; i++) {
      var o = slotOrigin(i)
      if (o.x < 0) continue
      var sz = (i === resultIdx || (i >= craftBase && i < craftBase + 4)) ? craftSlot : slot
      if (i === resultIdx) sz = craftSlot
      if (i >= craftBase && i < craftBase + 4) sz = craftSlot
      if (i >= armorBase && i < armorBase + 4) sz = armorSlot
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
    // Bottom while About is open so the normal About window sits in front;
    // Overlay otherwise so the panel covers the desktop like before.
    WlrLayershell.layer: root.aboutOpen ? WlrLayer.Bottom : WlrLayer.Overlay
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
        Keys.onPressed: function(ev) { root.handleInventoryKey(ev) }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          z: -1
          onPressed: function(mouse) {
            var bx = mouse.x / panel.s
            var by = mouse.y / panel.s
            // Tab grid first (apps / menu leaves), then classic/hotbar slots.
            if (root.selectedTab >= 0) {
              var mi = root.hitMenuSlot(bx, by)
              if (mi >= 0) {
                root.beginMenuDrag(mi)
                return
              }
            }
            root.beginDrag(root.hitSlot(bx, by))
          }
          onPositionChanged: function(mouse) {
            var bx = mouse.x / panel.s
            var by = mouse.y / panel.s
            root.moveDrag(bx, by)
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
              if (i >= 0) {
                label = root.menuSlotLabel(i)
                origin = root.menuSlotOrigin(i)
              } else {
                // Hotbar strip under the menu — hover/drag still works.
                i = root.hitSlot(bx, by)
                if (i >= root.hotbarBase && root.slots[i]) {
                  label = root.slots[i].name || ""
                  origin = root.slotOrigin(i)
                } else {
                  i = -1
                  origin = null
                }
              }
            } else {
              i = root.hitSlot(bx, by)
              if (i >= 0) {
                var it = root.slotDisplayItem(i)
                label = it ? it.name : ""
                origin = root.slotOrigin(i)
              }
              // Live suggestion context from hovered main/hotbar launcher.
              // Armor wells (0-3) and craft keep the current context so
              // suggestions stay clickable; empty space clears live context only.
              if (i >= root.mainBase)
                root.contextSlot = i
              else if (i < 0)
                root.contextSlot = -1
            }
            root.hoveredSlot = i
            if (label && origin) {
              root.showTip(label, panel.ox + (origin.x + 8) * panel.s, panel.oy + origin.y * panel.s - 4 * panel.s)
            } else if (root.selectedTab < 0 && root.hitPlayer(bx, by)) {
              root.showTip(
                root.steveCrouching ? "Steve (crouched)" : "Steve — click to sneak",
                panel.ox + (root.playerX + root.playerW / 2) * panel.s,
                panel.oy + root.playerY * panel.s - 4 * panel.s)
            } else {
              root.hideTip()
            }
          }
          onExited: {
            root.hoveredTab = -1
            root.contextSlot = -1
            root.hideTip()
          }
          onReleased: function(mouse) {
            var bx = mouse.x / panel.s
            var by = mouse.y / panel.s
            if (root.endDrag(bx, by)) return
            var ti = root.hitTab(bx, by)
            if (ti >= 0) {
              root.openTab(ti)
              return
            }
            if (root.selectedTab >= 0) {
              if (root.hitBack(bx, by) && root.goBackMenu())
                return
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
              // No menu hit — fall through so the hotbar row still launches.
            }
            var i = root.hitSlot(bx, by)
            if (i >= root.armorBase && i < root.armorBase + 4) {
              root.launchArmorWell(i)
              return
            }
            if (i >= root.craftBase && i <= root.resultIdx) {
              root.launchCraftWell(i)
              return
            }
            if (i >= root.mainBase) {
              root.pinnedSlot = i
              root.contextSlot = i
              root.launch(i)
              return
            }
            if (i >= 0) {
              root.launch(i)
            } else if (root.selectedTab < 0 && root.hitPlayer(bx, by)) {
              root.steveCrouching = !root.steveCrouching
            } else {
              root.pinnedSlot = -1
            }
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

            // When a tab is selected, draw its menu list + the live hotbar strip.
            if (root.selectedTab >= 0) {
              drawMenuView(ctx, s)
              drawHotbarStrip(ctx, s)
              return
            }

            // Player preview well — taller box aligned with the armor column
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
            // Scale figure to the bigger well (unit 2× gui scale, centered)
            var figU = 2 * s
            drawPlayer(ctx,
              plx + Math.floor((plw - 16 * figU) / 2),
              ply + Math.floor((plh - 26 * figU) / 2),
              figU)

            // Armor column wells (aligned to character box height)
            for (var a = 0; a < 4; a++) {
              var ao = root.slotOrigin(root.armorBase + a)
              var hotArmor = root.hoveredSlot === (root.armorBase + a)
              drawSlotFrame(ctx, ao.x * s, ao.y * s, root.armorSlot * s, s, false)
              if (hotArmor) {
                ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                ctx.fillRect(ao.x * s, ao.y * s, root.armorSlot * s, root.armorSlot * s)
              }
            }

            // Crafting 2×2 + result
            for (var c = 0; c < 4; c++) {
              var co = root.slotOrigin(root.craftBase + c)
              drawSlotFrame(ctx, co.x * s, co.y * s, root.craftSlot * s, s, false)
            }
            var ro = root.slotOrigin(root.resultIdx)
            drawSlotFrame(ctx, ro.x * s, ro.y * s, root.craftSlot * s, s, false)
            // Arrow between craft grid and result — centered on the 2×2
            // block (block height = craftPitch+craftSlot; visual center
            // craftY+17 → arrow y = craftY+16). Ends before craftResultX.
            drawArrow(ctx, (root.craftX + 36) * s, (root.craftY + 16) * s, s)

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
            // Armor wells: Steve's clothes recolored by tier. Craft/result: smart suggestions.
            for (var i = 0; i < root.slotCount; i++) {
              var isArmor = i >= root.armorBase && i < root.armorBase + 4
              var it = root.slotDisplayItem(i)
              var o = root.slotOrigin(i)
              if (o.x < 0) continue
              var sz = (i >= root.craftBase && i <= root.resultIdx) ? root.craftSlot : root.slot
              if (i === root.resultIdx) sz = root.craftSlot
              if (isArmor) sz = root.armorSlot
              if (root.dragFrom === i) continue

              if (i === root.hoveredSlot) {
                ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                ctx.fillRect(o.x * s, o.y * s, sz * s, sz * s)
              }
              if (!it) continue

              var slotDrew = false
              var drawUrl = it.iconUrl || root.slotIconUrls[i] || ""
              if (drawUrl) {
                var simg = root.appIconImage(drawUrl)
                if (simg && simg.status === Image.Ready) {
                  ctx.imageSmoothingEnabled = false
                  ctx.drawImage(simg,
                    (o.x + 1) * s, (o.y + 1) * s,
                    (sz - 2) * s, (sz - 2) * s)
                  ctx.imageSmoothingEnabled = true
                  slotDrew = true
                }
              }
              if (!slotDrew && it.rows) {
                var cmap = isArmor ? root.armorPaletteFor(it.colors) : it.colors
                var iw = it.rows[0].length
                var ih = it.rows.length
                var iox = o.x + Math.floor((sz - iw) / 2)
                var ioy = o.y + Math.floor((sz - ih) / 2)
                root.paintGrid(ctx, iox * s, ioy * s, s, it.rows, cmap)
                slotDrew = true
              }
              if (!slotDrew && it.glyph) {
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(8 * s) + "px Symbols Nerd Font, Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText(it.glyph, (o.x + sz / 2) * s, (o.y + sz / 2) * s)
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
                slotDrew = true
              }
              if (!slotDrew && it.name) {
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText(it.name.charAt(0).toUpperCase(), (o.x + sz / 2) * s, (o.y + sz / 2) * s)
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
              }
            }

            // Armor wells: durability-style bar under each piece (no
            // vertical glint — it drew a beige line through the item).
            {
              var atNow = root.armorTier()
              var nextT = root.armorNextThreshold(atNow.tone)
              var prevT = root.armorPrevThreshold(atNow.tone)
              for (var aw = 0; aw < 4; aw++) {
                var ao2 = root.slotOrigin(root.armorBase + aw)
                var barX = ao2.x
                var barY = ao2.y + root.armorSlot + 1
                var barW = root.armorSlot
                var barH = 3
                ctx.fillStyle = "#2a2a2a"
                ctx.fillRect(barX * s, barY * s, barW * s, barH * s)
                var prog = 1
                if (nextT !== null && nextT > prevT)
                  prog = Math.max(0, Math.min(1, (atNow.score - prevT) / (nextT - prevT)))
                else if (nextT === null)
                  prog = 1
                ctx.fillStyle = nextT === null ? "#5decd7" : "#80ff20"
                ctx.fillRect(barX * s, barY * s, Math.round(barW * prog) * s, barH * s)
              }
            }

            // Beacon beam — flashes above the armor column after Netherite.
            if (root.beaconUntil > Date.now() && root.selectedTab < 0) {
              var beamAlpha = Math.min(1, (root.beaconUntil - Date.now()) / 3500)
              var bx0 = (root.armorX + 4) * s
              var bw0 = 8 * s
              var by0 = (root.armorY - 6) * s
              var bh0 = (root.armorColH + 12) * s
              ctx.globalAlpha = 0.35 + 0.4 * Math.abs(Math.sin(Date.now() / 180))
              ctx.fillStyle = "#5decd7"
              ctx.fillRect(bx0, by0, bw0, bh0)
              ctx.fillStyle = "#ffffff"
              ctx.fillRect(bx0 + 2 * s, by0, Math.max(s, 2 * s), bh0)
              ctx.globalAlpha = beamAlpha
              ctx.fillStyle = "#aef7ef"
              ctx.fillRect(bx0 - s, by0, bw0 + 2 * s, 3 * s)
              ctx.globalAlpha = 1
            }

            // Particle crits (successful hotbar drops).
            if (root.critParticles.length) {
              for (var cp = 0; cp < root.critParticles.length; cp++) {
                var p = root.critParticles[cp]
                var life = Math.max(0, (root.critUntil - Date.now()) / 450)
                ctx.globalAlpha = life
                ctx.fillStyle = cp % 2 ? "#ffd43b" : "#ff6b6b"
                var psz = Math.max(s, Math.round(2 * s * life))
                ctx.fillRect(Math.round(p.x * s), Math.round(p.y * s), psz, psz)
                ctx.globalAlpha = 1
              }
            }

            // F3 debug overlay — metrics + coords flavor (classic view).
            if (root.debugOverlay) {
              var dbgX = root.pad * s
              var dbgY = root.mainY * s
              ctx.fillStyle = "rgba(0, 0, 0, 0.75)"
              ctx.fillRect(dbgX, dbgY, (root.panelW - 2 * root.pad) * s, 34 * s)
              ctx.fillStyle = "#5decd7"
              ctx.font = "bold " + String(5 * s) + "px Monocraft, monospace"
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
              var dAt = root.armorTier()
              ctx.fillText("MC Debug (F3)", dbgX + 2 * s, dbgY + 2 * s)
              ctx.fillStyle = "#e8e8f0"
              ctx.font = String(4 * s) + "px Monocraft, monospace"
              ctx.fillText("apps=" + root.appRows.length +
                " wins=" + root.metricWins +
                " hours=" + root.metricHours, dbgX + 2 * s, dbgY + 10 * s)
              ctx.fillText("armor=" + dAt.name + " " + dAt.score + "pts",
                dbgX + 2 * s, dbgY + 17 * s)
              ctx.fillText("fps≈60  scale=" + root.guiScale,
                dbgX + 2 * s, dbgY + 24 * s)
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
            }

            // Armor progression note — centered in the gap between the player
            // column and the main 3×9 grid (see noteY / noteCx).
            {
              var at = root.armorTier()
              ctx.fillStyle = "#404040"
              ctx.font = "bold " + String(5 * s) + "px Monocraft, monospace"
              ctx.textAlign = "center"
              ctx.textBaseline = "top"
              ctx.fillText(
                "Use Omarchy more to level up your armor",
                root.noteCx * s, root.noteY * s)
              ctx.fillStyle = "#505050"
              ctx.font = String(4 * s) + "px Monocraft, monospace"
              ctx.fillText(
                at.name + " · " + at.score + " pts · " +
                at.hours + "h · " + at.wins + " wins",
                root.noteCx * s, (root.noteY + 7) * s)
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
            }

            // Empty craft → rotating fun facts (permanent; always drawn
            // so a hover tooltip can't blank the line).
            if (!root.debugOverlay && root.selectedTab < 0) {
              var facts = [
                "Fun fact: Minecraft has over 300 million copies sold.",
                "Fun fact: Monocraft is an open pixel font.",
                "Fun fact: Cows will follow you if you hold wheat.",
                "Fun fact: The first Ender Dragon was purple.",
                "Fun fact: You can smelt cactus into green dye.",
                "Fun fact: Omarchy themes never sleep."
              ]
              ctx.fillStyle = "#3a3a3a"
              ctx.font = String(4 * s) + "px Monocraft, monospace"
              ctx.textAlign = "center"
              ctx.textBaseline = "top"
              ctx.fillText(
                facts[Math.floor(Date.now() / 6000) % facts.length],
                root.noteCx * s, (root.noteY + 13) * s)
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
            }

            // Suggested 4 apps listed under the craft boxes when a source
            // is hovered/pinned (room between craft block and note band).
            if (root.selectedTab < 0 && root.suggestSrc >= 0) {
              var sugList = root.suggestionsFor(root.suggestSrc)
              if (sugList.length) {
                ctx.fillStyle = "#3a3a3a"
                ctx.font = String(4 * s) + "px Monocraft, monospace"
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
                var sugY0 = root.craftY + 2 * root.craftPitch + 2
                for (var sg = 0; sg < sugList.length && sg < 4; sg++) {
                  ctx.fillText(
                    "· " + String(sugList[sg].name || ""),
                    root.craftX * s, (sugY0 + sg * 5) * s)
                }
              }
            }

            // Drag ghost follows the cursor (classic slots or menu/app payload).
            if (root.dragging) {
              var ghostRows = null
              var ghostColors = null
              if (root.dragPayload && root.dragPayload.rows && root.dragPayload.rows.length) {
                ghostRows = root.dragPayload.rows
                ghostColors = root.dragPayload.colors
              } else if (root.dragFrom >= 0) {
                var dit = root.slots[root.dragFrom]
                if (dit && dit.rows) {
                  ghostRows = dit.rows
                  ghostColors = dit.colors
                }
              }
              if (ghostRows) {
                ctx.globalAlpha = 0.85
                var diw = ghostRows[0].length
                var dih = ghostRows.length
                root.paintGrid(ctx,
                  Math.round((root.dragX - diw / 2) * s),
                  Math.round((root.dragY - dih / 2) * s),
                  s, ghostRows, ghostColors)
                ctx.globalAlpha = 1.0
              }
            }
          }

          function drawHotbarStrip(ctx, s) {
            // Hotbar strip bg
            ctx.fillStyle = "#8b8b8b"
            ctx.fillRect((root.pad - 1) * s, (root.hotbarY - 1) * s,
                         (root.cols * root.pitch + 2) * s, (root.slot + 2) * s)
            for (var h = 0; h < 9; h++) {
              var ho = root.slotOrigin(root.hotbarBase + h)
              drawSlotFrame(ctx, ho.x * s, ho.y * s, root.slot * s, s, false)
            }
            for (var i = root.hotbarBase; i < root.hotbarBase + 9; i++) {
              var it = root.slotDisplayItem(i)
              var o = root.slotOrigin(i)
              if (o.x < 0 || root.dragFrom === i) continue
              if (i === root.hoveredSlot) {
                ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                ctx.fillRect(o.x * s, o.y * s, root.slot * s, root.slot * s)
              }
              if (!it) continue
              var hotDrew = false
              var hotUrl = it.iconUrl || root.slotIconUrls[i] || ""
              if (hotUrl) {
                var himg = root.appIconImage(hotUrl)
                if (himg && himg.status === Image.Ready) {
                  ctx.imageSmoothingEnabled = false
                  ctx.drawImage(himg,
                    (o.x + 1) * s, (o.y + 1) * s,
                    (root.slot - 2) * s, (root.slot - 2) * s)
                  ctx.imageSmoothingEnabled = true
                  hotDrew = true
                }
              }
              if (!hotDrew && it.rows) {
                var iw = it.rows[0].length
                var ih = it.rows.length
                root.paintGrid(ctx,
                  (o.x + Math.floor((root.slot - iw) / 2)) * s,
                  (o.y + Math.floor((root.slot - ih) / 2)) * s,
                  s, it.rows, it.colors)
                hotDrew = true
              }
              if (!hotDrew && it.glyph) {
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(8 * s) + "px Symbols Nerd Font, Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText(it.glyph, (o.x + root.slot / 2) * s, (o.y + root.slot / 2) * s)
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
                hotDrew = true
              }
              if (!hotDrew && it.name) {
                ctx.fillStyle = "#e8e8f0"
                ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText(it.name.charAt(0).toUpperCase(), (o.x + root.slot / 2) * s, (o.y + root.slot / 2) * s)
                ctx.textAlign = "left"
                ctx.textBaseline = "top"
              }
            }
            // Drag ghost + hotbar drop-target highlight (tab view).
            if (root.dragging && (root.dragPayload || root.dragFrom >= 0)) {
              var dropTo = root.hitSlot(root.dragX, root.dragY)
              if (dropTo >= root.hotbarBase && dropTo < root.hotbarBase + 9) {
                var dro = root.slotOrigin(dropTo)
                ctx.fillStyle = "rgba(255, 255, 255, 0.45)"
                ctx.fillRect(dro.x * s, dro.y * s, root.slot * s, root.slot * s)
              }
              var ghostRows = null
              var ghostColors = null
              if (root.dragPayload && root.dragPayload.rows && root.dragPayload.rows.length) {
                ghostRows = root.dragPayload.rows
                ghostColors = root.dragPayload.colors
              } else if (root.dragFrom >= 0) {
                var dit = root.slots[root.dragFrom]
                if (dit && dit.rows) {
                  ghostRows = dit.rows
                  ghostColors = dit.colors
                }
              }
              if (ghostRows) {
                ctx.globalAlpha = 0.85
                var diw = ghostRows[0].length
                var dih = ghostRows.length
                root.paintGrid(ctx,
                  Math.round((root.dragX - diw / 2) * s),
                  Math.round((root.dragY - dih / 2) * s),
                  s, ghostRows, ghostColors)
                ctx.globalAlpha = 1.0
              }
            }
          }

          function drawMenuView(ctx, s) {
            var isApps = root.menuTabs[root.selectedTab].route === "apps"
            var items = isApps ? root.appRows : root.menuItems()
            var count = items.length

            // Back chip on the right of the title row when drilled into a submenu
            if (root.menuPath.length > 0) {
              ctx.fillStyle = "#6a6a6a"
              ctx.fillRect(root.backChipX * s, root.backChipY * s,
                           root.backChipW * s, root.backChipH * s)
              ctx.fillStyle = "#ffffff"
              ctx.font = "bold " + String(6 * s) + "px Monocraft, monospace"
              ctx.textAlign = "center"
              ctx.textBaseline = "middle"
              ctx.fillText("← Back",
                           (root.backChipX + root.backChipW / 2) * s,
                           (root.backChipY + root.backChipH / 2) * s)
              ctx.textAlign = "left"
              ctx.textBaseline = "top"
            }

            var y0 = root.menuGridY
            var x0 = root.menuGridX
            var show = count

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

            for (var i = 0; i < show; i++) {
              var o = root.menuSlotOrigin(i)
              // Hide the source cell while its payload is being dragged.
              var srcDrag = root.dragging && root.dragMenuFrom === i
              if (!srcDrag) {
                drawSlotFrame(ctx, o.x * s, o.y * s, root.slot * s, s, false)
                if (i === root.hoveredSlot) {
                  ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                  ctx.fillRect(o.x * s, o.y * s, root.slot * s, root.slot * s)
                }

                if (isApps) {
                  var a = root.appRows[i]
                  var name = a && a.name ? String(a.name) : "?"
                  var spr = a ? root.appSpriteFor(name) : null
                  var ip = 1
                  var ix = (o.x + ip) * s
                  var iy = (o.y + ip) * s
                  var isz = (root.slot - 2 * ip) * s
                  var drew = false
                  if (a && a.iconUrl) {
                    var img = root.appIconImage(a.iconUrl)
                    if (img && img.status === Image.Ready && img.paintedWidth > 0) {
                      ctx.imageSmoothingEnabled = false
                      ctx.drawImage(img, ix, iy, isz, isz)
                      ctx.imageSmoothingEnabled = true
                      drew = true
                    }
                  }
                  if (!drew && spr && spr.rows) {
                    var siw = spr.rows[0].length
                    var sih = spr.rows.length
                    root.paintGrid(ctx,
                      (o.x + Math.floor((root.slot - siw) / 2)) * s,
                      (o.y + Math.floor((root.slot - sih) / 2)) * s,
                      s, spr.rows, spr.colors)
                    drew = true
                  }
                  if (!drew) {
                    ctx.fillStyle = "#e8e8f0"
                    ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    ctx.fillText(name.charAt(0).toUpperCase() || "?",
                                 (o.x + root.slot / 2) * s,
                                 (o.y + root.slot / 2) * s)
                    ctx.textAlign = "left"
                    ctx.textBaseline = "top"
                  }
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
            // Detailed Steve preview — full pixel figure (16×26 units).
            // Crouch: shift the body down and compress the legs (sneak pose).
            // Armor tiers recolor tee / jeans / shoes to match the wells.
            var crouch = root.steveCrouching
            var dy = crouch ? 3 * s : 0
            var legTop = y + (crouch ? 21 : 18) * s
            var legH = (crouch ? 5 : 8) * s
            var tone = root.armorTier().tone
            var pal = root.armorTierPalettes[tone]
            var tee = tone ? pal[0] : "#8ecff0"
            var teeDark = tone ? pal[1] : "#5a9ec9"
            var jeans = tone ? pal[0] : "#4a3fa0"
            var jeansDark = tone ? pal[1] : "#3a3080"
            var shoes = tone ? pal[1] : "#6b4420"
            // head
            ctx.fillStyle = "#3a2a1a"
            ctx.fillRect(x + 4 * s, y + dy, 8 * s, 8 * s)
            ctx.fillStyle = "#c8a27a"
            ctx.fillRect(x + 5 * s, y + 2 * s + dy, 6 * s, 6 * s)
            // hair fringe
            ctx.fillStyle = "#3a2a1a"
            ctx.fillRect(x + 5 * s, y + 2 * s + dy, 6 * s, 1 * s)
            ctx.fillRect(x + 4 * s, y + dy, 8 * s, 2 * s)
            // eyes (white + pupil)
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(x + 5 * s, y + 4 * s + dy, 2 * s, 2 * s)
            ctx.fillRect(x + 9 * s, y + 4 * s + dy, 2 * s, 2 * s)
            ctx.fillStyle = "#3b5dc9"
            ctx.fillRect(x + 6 * s, y + 4 * s + dy, 1 * s, 2 * s)
            ctx.fillRect(x + 9 * s, y + 4 * s + dy, 1 * s, 2 * s)
            // nose shadow / mouth
            ctx.fillStyle = "#b88860"
            ctx.fillRect(x + 7 * s, y + 6 * s + dy, 2 * s, 1 * s)
            ctx.fillStyle = "#8a6040"
            ctx.fillRect(x + 6 * s, y + 7 * s + dy, 4 * s, 1 * s)
            // torso (tee with shading — armor palette when leveled)
            ctx.fillStyle = tee
            ctx.fillRect(x + 4 * s, y + 8 * s + dy, 8 * s, legTop - (y + 8 * s + dy))
            ctx.fillStyle = teeDark
            ctx.fillRect(x + 4 * s, y + 8 * s + dy, 8 * s, 2 * s)
            ctx.fillRect(x + 4 * s, legTop - 2 * s, 8 * s, 2 * s)
            // sleeves
            ctx.fillStyle = tee
            ctx.fillRect(x + 4 * s, y + 8 * s + dy, 2 * s, 4 * s)
            ctx.fillRect(x + 10 * s, y + 8 * s + dy, 2 * s, 4 * s)
            // arms (skin)
            ctx.fillStyle = "#c8a27a"
            var armH = Math.max(s, legTop - (y + 12 * s + dy))
            ctx.fillRect(x + 4 * s, y + 12 * s + dy, 2 * s, armH)
            ctx.fillRect(x + 10 * s, y + 12 * s + dy, 2 * s, armH)
            ctx.fillStyle = "#b88860"
            ctx.fillRect(x + 4 * s, legTop - 2 * s, 2 * s, 2 * s)
            ctx.fillRect(x + 10 * s, legTop - 2 * s, 2 * s, 2 * s)
            // legs (jeans with seam)
            ctx.fillStyle = jeans
            ctx.fillRect(x + 4 * s, legTop, 4 * s, legH)
            ctx.fillRect(x + 8 * s, legTop, 4 * s, legH)
            ctx.fillStyle = jeansDark
            ctx.fillRect(x + 7 * s, legTop, 2 * s, legH)
            // shoes
            ctx.fillStyle = shoes
            ctx.fillRect(x + 4 * s, legTop + legH - 2 * s, 4 * s, 2 * s)
            ctx.fillRect(x + 8 * s, legTop + legH - 2 * s, 4 * s, 2 * s)
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
