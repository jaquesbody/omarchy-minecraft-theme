import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property bool opened: false
  property int score: 0
  property int hoveredBtn: -1
  property string deathQuote: ""

  // Rotating death-screen flavor quotes (classic MC energy, original text).
  readonly property var quotes: [
    "Your armor was mere cloth against fate.",
    "Even diamonds crack under pressure.",
    "The void remembers your name.",
    "Respawn and try not to do that again.",
    "Pro tip: don't.",
    "Score is temporary. Glory is forever.",
    "Somewhere, a creeper is laughing.",
    "You died doing what you loved: computing."
  ]

  function open(payload) {
    try {
      var p = typeof payload === "string" && payload ? JSON.parse(payload) : (payload || {})
      if (p.score !== undefined) score = Number(p.score) || 0
      else score = Math.floor(Math.random() * 500)
    } catch (e) {
      score = Math.floor(Math.random() * 500)
    }
    deathQuote = quotes[Math.floor(Math.random() * quotes.length)]
    opened = true
    hoveredBtn = -1
    Quickshell.execDetached([
      "pw-play", Quickshell.env("HOME") + "/.local/share/minecraft-theme/sounds/death.wav"
    ])
  }

  function close() { opened = false; hoveredBtn = -1 }

  // Classic death-screen actions, remapped to session power controls.
  // 0 Respawn (cancel) · 1 Title Screen (lock) · 2 Log Out · 3 Restart · 4 Shut Down
  readonly property var actions: [
    { label: "Respawn", cmd: [] },
    { label: "Title Screen", cmd: ["omarchy-system-lock"] },
    { label: "Log Out", cmd: ["omarchy-system-logout"] },
    { label: "Restart", cmd: ["omarchy-system-reboot"] },
    { label: "Shut Down", cmd: ["omarchy-system-shutdown"] }
  ]

  function activate(i) {
    var a = actions[i]
    if (!a) return
    if (a.cmd && a.cmd.length)
      Quickshell.execDetached(a.cmd)
    close()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "minecraft-death"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: hitRoot }

    readonly property int s: 2

    Item {
      id: hitRoot
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.close()
      Keys.onReturnPressed: root.activate(0)
      Keys.onEnterPressed: root.activate(0)
      // Up/Down move selection among the 5 buttons
      Keys.onUpPressed: root.hoveredBtn = (root.hoveredBtn + root.actions.length - 1) % root.actions.length
      Keys.onDownPressed: root.hoveredBtn = (root.hoveredBtn + 1) % root.actions.length

      // Blood-red full-screen wash (MC death overlay tint)
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.55, 0.0, 0.0, 0.55)
      }

      // Dim base so text pops
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }

      Column {
        anchors.centerIn: parent
        spacing: 14
        z: 1

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "You Died!"
          color: "#ffffff"
          font.family: "Monocraft"
          font.pixelSize: 40
          font.bold: true
          style: Text.Raised
          styleColor: "#3f0000"
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Score: " + root.score
          color: "#ffffff"
          font.family: "Monocraft"
          font.pixelSize: 16
          style: Text.Raised
          styleColor: "#3f0000"
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 420
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.deathQuote
          color: "#ffd0d0"
          font.family: "Monocraft"
          font.pixelSize: 12
          opacity: 0.95
        }

        // Button column — classic wide gray buttons, original bevel
        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8

          Repeater {
            model: root.actions.length
            delegate: Rectangle {
              id: btn
              required property int index
              width: 240
              height: 36
              color: root.hoveredBtn === index ? "#6a6a6a" : "#5a5a5a"
              border.color: "#000000"
              border.width: 2

              // Bevel
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 2
                color: "#9e9e9e"
              }
              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                color: "#9e9e9e"
              }
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: "#2e2e2e"
              }
              Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                color: "#2e2e2e"
              }

              // Hover outline (white, MC-style)
              Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                color: "transparent"
                border.color: root.hoveredBtn === index ? "#ffffff" : "transparent"
                border.width: 2
                visible: root.hoveredBtn === index
              }

              Text {
                anchors.centerIn: parent
                text: root.actions[btn.index].label
                color: root.hoveredBtn === index ? "#ffffa0" : "#ffffff"
                font.family: "Monocraft"
                font.pixelSize: 15
                style: Text.Raised
                styleColor: "#3f3f3f"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.hoveredBtn = btn.index
                onExited: if (root.hoveredBtn === btn.index) root.hoveredBtn = -1
                onClicked: {
                  Quickshell.execDetached([
                    "pw-play", Quickshell.env("HOME") + "/.local/share/minecraft-theme/sounds/click.wav"
                  ])
                  root.activate(btn.index)
                }
              }
            }
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Esc to cancel · ↑↓ select · Enter respawn"
          color: "#ffb0b0"
          font.family: "Monocraft"
          font.pixelSize: 11
          opacity: 0.85
        }
      }
    }
  }
}
