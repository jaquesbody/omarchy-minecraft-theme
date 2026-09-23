import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking

Item {
  id: root

  property bool opened: false
  function open(payload) {
    opened = true
    try {
      var p = typeof payload === "string" && payload ? JSON.parse(payload) : (payload || {})
      if (p && p.slot !== undefined && p.slot !== null) {
        var n = Number(p.slot)
        if (isFinite(n))
          selectedSlot = Math.max(0, Math.min(8, Math.round(n)))
      }
    } catch (e) {}
  }
  function close() { opened = false }

  // Whole-number GUI scale so every pixel stays crisp.
  property int guiScale: 2
  property int selectedSlot: 0

  // Hover tooltip (panel-local coords). Owner prevents cross-area hide races.
  property string tipText: ""
  property real tipX: 0
  property real tipY: 0
  property bool tipVisible: false
  property string tipOwner: ""
  function showTip(text, x, y, owner) {
    tipOwner = owner || ""
    tipText = String(text || "")
    tipX = x
    tipY = y
    tipVisible = tipText.length > 0
  }
  function hideTip(owner) {
    if (owner && tipOwner && tipOwner !== owner)
      return
    tipOwner = ""
    tipVisible = false
  }

  // --- volume (Pipewire) ---
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  readonly property bool volumeMuted: root.sink && root.sink.audio ? !!root.sink.audio.muted : false
  readonly property int volumePct: {
    if (!root.sink || !root.sink.audio) return 0
    return Math.round(Math.max(0, Math.min(1, root.sink.audio.volume)) * 100)
  }

  // --- battery (UPower) ---
  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: !!(root.batteryDevice && root.batteryDevice.isPresent)
  readonly property int batteryPct: {
    if (!root.batteryPresent) return 100
    return Math.round(Math.max(0, Math.min(1, root.batteryDevice.percentage || 0)) * 100)
  }

  // --- network (NetworkManager via Quickshell.Networking) ---
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }
  function findConnectedWifiNetwork(device) {
    var networks = device && device.networks ? device.networks.values : []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork(wifiDevice)
  readonly property bool wifiWired: !!(wiredDevice && wiredDevice.connected)
  readonly property string wifiSsid: connectedWifiNetwork ? String(connectedWifiNetwork.ssid || "") : ""
  readonly property int wifiPct: {
    if (wifiWired) return 100
    if (connectedWifiNetwork) return Math.round((connectedWifiNetwork.signalStrength || 0) * 100)
    return 0
  }
  readonly property string wifiTip: {
    if (wifiWired) return "Ethernet: 100%"
    if (connectedWifiNetwork) return "Wi‑Fi " + wifiSsid + ": " + wifiPct + "%"
    return "Network: disconnected"
  }

  // --- RAM used% (/proc/meminfo, refreshed only while open) ---
  property int ramUsedPct: 0
  function parseMeminfo(raw) {
    var mt = /MemTotal:\s+(\d+)/.exec(String(raw || ""))
    var ma = /MemAvailable:\s+(\d+)/.exec(String(raw || ""))
    if (!mt || !ma) return
    var t = parseInt(mt[1], 10)
    var a = parseInt(ma[1], 10)
    if (!isFinite(t) || t <= 0 || !isFinite(a)) return
    ramUsedPct = Math.max(0, Math.min(100, Math.round((t - a) * 100 / t)))
  }
  FileView {
    id: meminfoFile
    path: "/proc/meminfo"
    watchChanges: false
    printErrors: false
    onLoaded: root.parseMeminfo(text())
    onLoadFailed: {}
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: meminfoFile.reload()
  }

  readonly property real xpProgress: batteryPresent
    ? Math.max(0, Math.min(1, batteryPct / 100)) : 0
  readonly property int xpLevel: batteryPresent
    ? Math.max(0, Math.min(100, batteryPct)) : 0

  readonly property string volumeTip: volumeMuted
    ? "Volume: muted" : "Volume: " + volumePct + "%"
  readonly property string ramTip: "RAM: " + ramUsedPct + "% used"
  readonly property string batteryTip: batteryPresent
    ? "Battery: " + batteryPct + "%" : "Battery: none"

  onGuiScaleChanged: hud.requestPaint()
  onSelectedSlotChanged: hud.requestPaint()
  onBatteryPctChanged: hud.requestPaint()
  onBatteryPresentChanged: hud.requestPaint()
  onVolumeMutedChanged: hud.requestPaint()
  onVolumePctChanged: hud.requestPaint()
  onWifiPctChanged: hud.requestPaint()
  onWifiSsidChanged: hud.requestPaint()
  onWifiWiredChanged: hud.requestPaint()
  onRamUsedPctChanged: hud.requestPaint()
  onOpenedChanged: {
    hud.requestPaint()
    if (!opened) hideTip()
  }

  // Original pixel-art grids (no Mojang assets). "." = transparent.
  readonly property var gridHeart: [
    ".##...##.",
    "#XX###XX#",
    "#hXXXXXX#",
    "#XXXXXXX#",
    ".#XXXXX#.",
    "..#XXX#..",
    "...#X#...",
    "....#....",
    "........."
  ]
  readonly property var mapHeart: {
    "#": "#120404",
    "X": "#ff2a2a",
    "h": "#ffb0b0"
  }
  readonly property var mapHeartEmpty: {
    "#": "#120404",
    "X": "#1a1a1a",
    "h": "#1a1a1a"
  }

  // Slender chicken drumstick — meat top-left, thin bone bottom-right. All rows 9 wide.
  readonly property var gridHunger: [
    "..###...",
    ".#mmm#..",
    "#mmmm#..",
    "#mmmm#..",
    "#mmm##..",
    ".#m#ww#.",
    "..#www#.",
    "...##w#.",
    ".....##."
  ]
  readonly property var mapHunger: {
    "#": "#120c04",
    "m": "#a35d2a",
    "w": "#efe6d8"
  }
  readonly property var mapHungerEmpty: {
    "#": "#120c04",
    "m": "#3a2a14",
    "w": "#3a2a14"
  }

  // T-shirt (armor row = RAM used%). All rows 9 wide.
  readonly property var gridArmor: [
    ".##...##.",
    "#AaaaaaA#",
    "#AaaaaaA#",
    "#AaaaaaA#",
    "##aaaaa##",
    ".#aaaaa#.",
    ".#aaaaa#.",
    ".#AaaaA#.",
    "..#aaa#.."
  ]
  readonly property var mapArmor: {
    "#": "#0a1018",
    "a": "#9fb4c8",
    "A": "#e8f4ff"
  }
  readonly property var mapArmorEmpty: {
    "#": "#0a1018",
    "a": "#2a3440",
    "A": "#2a3440"
  }

  // --- Slot items: OG app icons, simply pixelated — sized to fill a 20×20 cell ---

  // 0. Brave — plain orange shield
  readonly property var gridBrave: [
    "....#######...",
    "...#ooooooo#..",
    "..#ooooooooo#.",
    "..#ooooooooo#.",
    "..#ooooooooo#.",
    "..#ooooooooo#.",
    "..#ooooooooo#.",
    "..#ooooooooo#.",
    "..#ooooooooo#.",
    "...#ooooooo#..",
    "....#ooooo#...",
    ".....#ooo#....",
    "......###....."
  ]
  readonly property var mapBrave: {
    "#": "#3a1004",
    "o": "#fb542b"
  }

  // 1. Terminal (foot) — dark screen, green prompt + block cursor. All rows 13 wide.
  readonly property var gridTerminal: [
    "#############",
    "#kkkkkkkkkkk#",
    "#kkkkkkkkkkk#",
    "#kg#kkkkkkkk#",
    "#kkkgkkkkkkk#",
    "#kkkkg#######",
    "#kkkkkkkkkkk#",
    "#kkkkkkkkkkk#",
    "#kg##########",
    "#kgggggggggg#",
    "#kkkkkkkkkkk#",
    "#kkkkkkkkkkk#",
    "#############"
  ]
  readonly property var mapTerminal: {
    "#": "#0a0a0c",
    "k": "#141418",
    "g": "#3ddf6e"
  }

  // 2. OpenCode — dark frame with light inner field (brand mark)
  readonly property var gridOpenCode: [
    "#############",
    "#...........#",
    "#.#########.#",
    "#.#.......#.#",
    "#.#.#####.#.#",
    "#.#.#...#.#.#",
    "#.#.#...#.#.#",
    "#.#.#####.#.#",
    "#.#.......#.#",
    "#.#########.#",
    "#...........#",
    "#############",
    "#############"
  ]
  readonly property var mapOpenCode: {
    "#": "#211e1e",
    ".": "#f2f0ec"
  }

  // 3. Obsidian — purple crystal
  readonly property var gridObsidian: [
    "....#....",
    "...#p#...",
    "..#pPp#..",
    ".#pPPPp#.",
    "#pPPPPPp#",
    "#pPPPPPp#",
    ".#pPPPp#.",
    "..#pPp#..",
    "...#p#...",
    "....#...."
  ]
  readonly property var mapObsidian: {
    "#": "#1a1030",
    "p": "#6d3ccc",
    "P": "#b48cff"
  }

  // 4. X — white X on black tile
  readonly property var gridX: [
    "#############",
    "#WW#######WW#",
    "#WWW#####WWW#",
    "#.WWW###WWW.#",
    "#..WWW.WWW..#",
    "#...WWWWW...#",
    "#....WWW....#",
    "#...WWWWW...#",
    "#..WWW.WWW..#",
    "#.WWW###WWW.#",
    "#WWW#####WWW#",
    "#WW#######WW#",
    "#############"
  ]
  readonly property var mapX: {
    "#": "#0d0d0d",
    "W": "#f5f5f5",
    ".": "#0d0d0d"
  }

  // 5. Yakihonne — white tile, simple purple Y
  readonly property var gridYakihonne: [
    "#############",
    "#wwwwwwwwwww#",
    "#wWwwwwwWwww#",
    "#wWwwwwwWwww#",
    "#wwWwwwwWwww#",
    "#wwwWwwWwwww#",
    "#wwwwWWWwwww#",
    "#wwwwwwWwwww#",
    "#wwwwwwWwwww#",
    "#wwwwwwWwwww#",
    "#wwwwwwwwwww#",
    "#wwwwwwwwwww#",
    "#############"
  ]
  readonly property var mapYakihonne: {
    "#": "#4a0848",
    "w": "#f7f2f7",
    "W": "#840c84"
  }

  // 6. Files — blue folder with raised tab
  readonly property var gridFiles: [
    ".bb..........",
    ".bbbbbb......",
    ".bbbbbbbbbb..",
    "#############",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#bbbbbbbbbbb#",
    "#############"
  ]
  readonly property var mapFiles: {
    "#": "#0a2a4a",
    "b": "#4a9eff",
    ".": "#00000000"
  }

  // 7. Proton Mail — purple envelope, white flap
  readonly property var gridProton: [
    "#############",
    "#ppppppppppp#",
    "#pPPPPPPPPPp#",
    "#pPPPPPPPPPp#",
    "#pPp#####pPp#",
    "#pPPp###pPPp#",
    "#pPPPp#pPPPp#",
    "#pPPPP#PPPPp#",
    "#pPPP#P#PPPp#",
    "#pPP#PPP#PPp#",
    "#pP#PPPPP#Pp#",
    "#p#PPPPPPP#p#",
    "#############"
  ]
  readonly property var mapProton: {
    "#": "#2a1a6a",
    "p": "#6d4aff",
    "P": "#8b6cff"
  }

  // 8. YouTube — red tile, white play triangle
  readonly property var gridYoutube: [
    ".###########.",
    "#rrrrrrrrrrr#",
    "#rrrrrrrrrrr#",
    "#rWWrrrrrrrr#",
    "#rWWWrrrrrrr#",
    "#rWWWWrrrrrr#",
    "#rWWWWWrrrrr#",
    "#rWWWWWWrrrr#",
    "#rWWWWWrrrrr#",
    "#rWWWWrrrrrr#",
    "#rWWWrrrrrrr#",
    "#rWWrrrrrrrr#",
    ".###########."
  ]
  readonly property var mapYoutube: {
    "#": "#7a0000",
    "r": "#ff0000",
    "W": "#ffffff"
  }

  // 9-slot hotbar: name + launch argv + art. User order.
  readonly property var slots: [
    {
      name: "Brave Search",
      cmd: ["omarchy-launch-browser", "https://search.brave.com"],
      rows: root.gridBrave, colors: root.mapBrave
    },
    {
      name: "Terminal",
      cmd: ["omarchy-launch-terminal"],
      rows: root.gridTerminal, colors: root.mapTerminal
    },
    {
      name: "OpenCode",
      cmd: ["omarchy-launch-terminal", "opencode"],
      rows: root.gridOpenCode, colors: root.mapOpenCode
    },
    {
      name: "Obsidian",
      cmd: ["uwsm-app", "--", "obsidian"],
      rows: root.gridObsidian, colors: root.mapObsidian
    },
    {
      name: "X",
      cmd: ["omarchy-launch-webapp", "https://x.com/"],
      rows: root.gridX, colors: root.mapX
    },
    {
      name: "Yakihonne",
      cmd: ["omarchy-launch-webapp", "https://yakihonne.com"],
      rows: root.gridYakihonne, colors: root.mapYakihonne
    },
    {
      name: "Files",
      cmd: ["omarchy-launch-nautilus"],
      rows: root.gridFiles, colors: root.mapFiles
    },
    {
      name: "Proton Mail",
      cmd: ["omarchy-launch-webapp", "https://mail.proton.me"],
      rows: root.gridProton, colors: root.mapProton
    },
    {
      name: "YouTube",
      cmd: ["omarchy-launch-webapp", "https://youtube.com/"],
      rows: root.gridYoutube, colors: root.mapYoutube
    }
  ]

  function launchSlot(i) {
    var sl = slots[i]
    if (!sl || !sl.cmd || !sl.cmd.length)
      return
    Quickshell.execDetached(sl.cmd)
  }

  function openInventory() {
    Quickshell.execDetached([
      "omarchy-shell", "shell", "summon",
      "io.github.jaquesbody.minecraft-inventory", "{}"
    ])
  }

  function paintGrid(ctx, ox, oy, s, rows, cmap) {
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r];
      for (var c = 0; c < row.length; c++) {
        var col = cmap[row[c]];
        if (!col)
          continue;
        ctx.fillStyle = col;
        ctx.fillRect(ox + c * s, oy + r * s, s, s);
      }
    }
  }

  function paintHeartRow(ctx, hx, y, s, pct) {
    var gw = root.gridHeart[0].length;
    var gh = root.gridHeart.length;
    for (var i = 0; i < 10; i++) {
      var fill = root.volumeMuted ? 0
        : Math.max(0, Math.min(1, (pct - i * 10) / 10));
      var ox = hx + i * 8 * s;
      if (fill >= 0.999) {
        root.paintGrid(ctx, ox, y, s, root.gridHeart, root.mapHeart);
      } else if (fill >= 0.5) {
        root.paintGrid(ctx, ox, y, s, root.gridHeart, root.mapHeartEmpty);
        ctx.save();
        ctx.beginPath();
        ctx.rect(ox, y, Math.ceil(gw * s * 0.5), gh * s);
        ctx.clip();
        root.paintGrid(ctx, ox, y, s, root.gridHeart, root.mapHeart);
        ctx.restore();
      } else {
        root.paintGrid(ctx, ox, y, s, root.gridHeart, root.mapHeartEmpty);
      }
    }
  }

  function paintHungerRow(ctx, hx, hw, y, s, pct) {
    var gw = root.gridHunger[0].length;
    var gh = root.gridHunger.length;
    for (var i = 0; i < 10; i++) {
      // i=0 is the rightmost drumstick — signal grows from the right.
      var fill = Math.max(0, Math.min(1, (pct - i * 10) / 10));
      var ox = hx + hw - 9 * s - i * 8 * s;
      if (fill >= 0.999) {
        root.paintGrid(ctx, ox, y, s, root.gridHunger, root.mapHunger);
      } else if (fill >= 0.5) {
        root.paintGrid(ctx, ox, y, s, root.gridHunger, root.mapHungerEmpty);
        ctx.save();
        ctx.beginPath();
        // Half fill lives on the RIGHT of each drumstick (signal strengthens right→left across the row).
        var cut = Math.floor(gw * s * 0.5);
        ctx.rect(ox + cut, y, gw * s - cut, gh * s);
        ctx.clip();
        root.paintGrid(ctx, ox, y, s, root.gridHunger, root.mapHunger);
        ctx.restore();
      } else {
        root.paintGrid(ctx, ox, y, s, root.gridHunger, root.mapHungerEmpty);
      }
    }
  }

  function paintArmorRow(ctx, hx, y, s, pct) {
    var gw = root.gridArmor[0].length;
    var gh = root.gridArmor.length;
    for (var i = 0; i < 10; i++) {
      var fill = Math.max(0, Math.min(1, (pct - i * 10) / 10));
      var ox = hx + i * 8 * s;
      if (fill >= 0.999) {
        root.paintGrid(ctx, ox, y, s, root.gridArmor, root.mapArmor);
      } else if (fill >= 0.5) {
        root.paintGrid(ctx, ox, y, s, root.gridArmor, root.mapArmorEmpty);
        ctx.save();
        ctx.beginPath();
        ctx.rect(ox, y, Math.ceil(gw * s * 0.5), gh * s);
        ctx.clip();
        root.paintGrid(ctx, ox, y, s, root.gridArmor, root.mapArmor);
        ctx.restore();
      } else {
        root.paintGrid(ctx, ox, y, s, root.gridArmor, root.mapArmorEmpty);
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "minecraft-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Input only on the HUD band + inventory chip; rest of screen stays click-through.
    mask: Region { item: hitRoot }

    readonly property int s: root.guiScale
    // Larger hotbar (pitch 22, inner 20) so hearts/drumsticks/100% have breathing room.
    // Hearts/drumsticks keep the same sprite size as before.
    readonly property int cellPitch: 22
    readonly property int cellInner: 20
    readonly property int hotbarW: (1 + cellPitch * 9 + 1) * s
    readonly property int hotbarH: (2 + cellInner + 2) * s
    readonly property int xpH: 5 * s
    readonly property int gap: s
    readonly property int hotbarX: Math.round((width - hotbarW) / 2)
    readonly property int hotbarY: height - gap - hotbarH
    readonly property int xpY: hotbarY - gap - xpH
    readonly property int statusY: xpY - gap - 9 * s
    readonly property int armorY: statusY - gap - 9 * s

    // Inventory chip — traditional bottom-right "[E] inventory".
    readonly property int invW: 118 * s
    readonly property int invH: 16 * s
    readonly property int invMargin: 8 * s
    readonly property int invX: width - invMargin - invW
    readonly property int invY: height - invMargin - invH

    // Single hit root bounding every interactive region (hotbar, stat rows, inv chip).
    // Visuals for the inv chip are painted on the canvas; this layer is input-only.
    Item {
      id: hitRoot
      z: 10
      x: panel.hotbarX
      y: panel.armorY - panel.s
      width: (panel.invX + panel.invW) - panel.hotbarX
      height: panel.height - hitRoot.y

      // --- Hotbar slots: one hit-test MouseArea (same pattern as inventory) ---
      Item {
        id: hotbarArea
        x: 0
        y: panel.hotbarY - hitRoot.y
        width: panel.hotbarW
        height: panel.hotbarH

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          property int hoverIndex: -1
          function indexAt(mx) {
            var u = mx / panel.s
            var idx = Math.floor((u - 1) / panel.cellPitch)
            return (idx >= 0 && idx < 9) ? idx : -1
          }
          onPositionChanged: function(mouse) {
            var idx = indexAt(mouse.x)
            hoverIndex = idx
            if (idx >= 0 && root.slots[idx])
              root.showTip(root.slots[idx].name,
                panel.hotbarX + (1 + panel.cellPitch * idx + panel.cellPitch / 2) * panel.s,
                panel.hotbarY - 4 * panel.s, "hotbar")
            else
              root.hideTip("hotbar")
          }
          onExited: {
            hoverIndex = -1
            root.hideTip("hotbar")
          }
          onClicked: function(mouse) {
            var idx = indexAt(mouse.x)
            if (idx >= 0) {
              root.selectedSlot = idx
              root.launchSlot(idx)
            }
          }
        }
      }

      // --- Stat hover zones (tooltips) ---
      MouseArea {
        x: 0
        y: panel.armorY - hitRoot.y
        width: 10 * 8 * panel.s + 9 * panel.s
        height: 9 * panel.s
        hoverEnabled: true
        onContainsMouseChanged: {
          if (containsMouse) root.showTip(root.ramTip, panel.hotbarX + width / 2, panel.armorY - 4 * panel.s, "armor")
          else root.hideTip("armor")
        }
      }
      MouseArea {
        x: 0
        y: panel.statusY - hitRoot.y
        width: 10 * 8 * panel.s + 9 * panel.s
        height: 9 * panel.s
        hoverEnabled: true
        onContainsMouseChanged: {
          if (containsMouse) root.showTip(root.volumeTip, panel.hotbarX + width / 2, panel.statusY - 4 * panel.s, "volume")
          else root.hideTip("volume")
        }
      }
      MouseArea {
        x: panel.hotbarW - (10 * 8 * panel.s + 9 * panel.s)
        y: panel.statusY - hitRoot.y
        width: 10 * 8 * panel.s + 9 * panel.s
        height: 9 * panel.s
        hoverEnabled: true
        onContainsMouseChanged: {
          if (containsMouse) root.showTip(root.wifiTip, panel.hotbarX + x + width / 2, panel.statusY - 4 * panel.s, "wifi")
          else root.hideTip("wifi")
        }
      }
      MouseArea {
        x: 0
        y: panel.xpY - hitRoot.y
        width: panel.hotbarW
        height: panel.xpH
        hoverEnabled: true
        onContainsMouseChanged: {
          if (containsMouse && root.batteryPresent)
            root.showTip(root.batteryTip, panel.hotbarX + panel.hotbarW / 2, panel.xpY - 4 * panel.s, "xp")
          else root.hideTip("xp")
        }
      }

      // --- Inventory chip hit target (visual painted on canvas) ---
      MouseArea {
        id: invHit
        x: panel.invX - hitRoot.x
        y: panel.invY - hitRoot.y
        width: panel.invW
        height: panel.invH
        hoverEnabled: true
        onContainsMouseChanged: {
          hud.requestPaint()
          if (containsMouse) root.showTip("Inventory", panel.invX + panel.invW / 2, panel.invY - 4 * panel.s, "inv")
          else root.hideTip("inv")
        }
        onClicked: root.openInventory()
      }
    }

    Canvas {
      id: hud
      z: 1
      anchors.fill: parent

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (width <= 0 || height <= 0)
          return

        var s = panel.s
        var pitch = panel.cellPitch
        var inner = panel.cellInner
        var hx = panel.hotbarX
        var hy = panel.hotbarY
        var hw = panel.hotbarW
        var hh = panel.hotbarH

        // Hotbar body
        ctx.fillStyle = "rgba(15, 15, 18, 0.82)"
        ctx.fillRect(hx, hy, hw, hh)

        // Slot backgrounds
        for (var i = 0; i < 9; i++) {
          var cx = hx + (1 + pitch * i) * s
          var cy = hy + 2 * s
          ctx.fillStyle = "rgba(139, 139, 139, 0.28)"
          ctx.fillRect(cx, cy, inner * s, inner * s)
        }

        // Outer border
        ctx.fillStyle = "#000000"
        ctx.globalAlpha = 0.95
        ctx.fillRect(hx, hy, hw, s)
        ctx.fillRect(hx, hy + hh - s, hw, s)
        ctx.fillRect(hx, hy, s, hh)
        ctx.fillRect(hx + hw - s, hy, s, hh)
        ctx.globalAlpha = 1

        // Selected-slot frame
        var fi = root.selectedSlot
        if (fi >= 0 && fi < 9) {
          var fx = hx + (pitch * fi) * s
          var fw = (pitch + 2) * s
          var fh = (inner + 4) * s
          ctx.fillStyle = "#ffffff"
          ctx.globalAlpha = 0.95
          ctx.fillRect(fx, hy, fw, s)
          ctx.fillRect(fx, hy + fh - s, fw, s)
          ctx.fillRect(fx, hy, s, fh)
          ctx.fillRect(fx + fw - s, hy, s, fh)
          ctx.globalAlpha = 1
        }

        // Item icons — fill the 20×20 inner box (centered when art is smaller)
        for (var j = 0; j < 9; j++) {
          var item = root.slots[j]
          if (!item)
            continue
          var gx = hx + (1 + pitch * j) * s
          var gy = hy + 2 * s
          var iw = item.rows[0].length
          var ih = item.rows.length
          var ox = gx + Math.floor((inner - iw) / 2) * s
          var oy = gy + Math.floor((inner - ih) / 2) * s
          root.paintGrid(ctx, ox, oy, s, item.rows, item.colors)
        }

        // XP bar (battery); hidden on machines without a battery
        if (root.batteryPresent) {
          var xy = panel.xpY
          ctx.fillStyle = "rgba(0, 0, 0, 0.85)"
          ctx.fillRect(hx, xy, hw, panel.xpH)
          var fillW = Math.round((hw - 2 * s) * root.xpProgress)
          if (fillW > 0) {
            ctx.fillStyle = "#80ff20"
            ctx.fillRect(hx + s, xy + s, fillW, panel.xpH - 2 * s)
          }
        }

        // Hearts (left) — system volume
        root.paintHeartRow(ctx, hx, panel.statusY, s, root.volumePct)

        // Hunger/drumsticks (right) — wifi strength
        root.paintHungerRow(ctx, hx, hw, panel.statusY, s, root.wifiPct)

        // Armor (above hearts) — RAM usage
        root.paintArmorRow(ctx, hx, panel.armorY, s, root.ramUsedPct)

        // Inventory chip — bottom-right "[E] inventory"
        var bx = panel.invX
        var by = panel.invY
        var bw = panel.invW
        var bh = panel.invH
        var hovered = invHit && invHit.containsMouse
        ctx.fillStyle = hovered ? "rgba(40, 40, 48, 0.95)" : "rgba(15, 15, 18, 0.88)"
        ctx.beginPath()
        var rad = 3 * s
        ctx.moveTo(bx + rad, by)
        ctx.lineTo(bx + bw - rad, by)
        ctx.quadraticCurveTo(bx + bw, by, bx + bw, by + rad)
        ctx.lineTo(bx + bw, by + bh - rad)
        ctx.quadraticCurveTo(bx + bw, by + bh, bx + bw - rad, by + bh)
        ctx.lineTo(bx + rad, by + bh)
        ctx.quadraticCurveTo(bx, by + bh, bx, by + bh - rad)
        ctx.lineTo(bx, by + rad)
        ctx.quadraticCurveTo(bx, by, bx + rad, by)
        ctx.closePath()
        ctx.fill()
        ctx.strokeStyle = hovered ? "#ffffff" : "#000000"
        ctx.lineWidth = Math.max(1, s / 2)
        ctx.stroke()
        ctx.fillStyle = hovered ? "#ffffff" : "#c8c8c8"
        ctx.font = "bold " + String(7 * s) + "px Monocraft, monospace"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("[SUPER+E] inventory", bx + bw / 2, by + bh / 2)
        ctx.textAlign = "start"
        ctx.textBaseline = "alphabetic"
      }
    }

    // Battery % sits ABOVE the XP bar line (not on the bar).
    Text {
      id: xpLevelText
      z: 8
      visible: root.opened && root.batteryPresent
      text: String(root.xpLevel) + "%"
      color: "#80ff20"
      style: Text.Outline
      styleColor: "#000000"
      font {
        family: "Monocraft"
        pixelSize: 8 * panel.s
        bold: true
      }
      x: panel.hotbarX + Math.round((panel.hotbarW - width) / 2)
      y: panel.xpY - height - Math.round(panel.s * 0.5)
    }

    // Hover tooltip bubble — visual only (no MouseArea). Sits above canvas
    // and battery % text but below hitRoot so it never steals clicks.
    Rectangle {
      id: tipBubble
      z: 9
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
