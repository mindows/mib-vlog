pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons

// MIB Vlog — the recording surface.
//
// A fullscreen layer holds one 2:1 card: the front camera fills it as the
// background, and the mission HUD (Hud.qml) sits on top. Takes are recorded
// with that HUD burned in: a second, off-screen copy of it at the video's
// size is snapshotted as the take runs, and finalize.sh composites the
// snapshots when the take is saved.
//
// The camera is only `active` while the overlay is open, so closing the panel
// releases /dev/video* and drops the webcam LED instead of holding the device
// for the life of the shell.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  // The card shows either the feed or its settings, never both.
  property bool settingsOpen: false
  onSettingsOpenChanged: if (!settingsOpen && root.opened) keyCatcher.forceActiveFocus()

  // Labels, launch date, clock, hostname, and the entry counter.
  SettingsStore {
    id: store
    live: root.opened
  }

  // Current conditions for the WEATHER readout, and the location lookups
  // the settings face uses.
  Weather {
    id: weather
    store: store
    live: root.opened
  }

  readonly property string pluginId: (manifest && manifest.id) || "mib-vlog"
  readonly property color hud: "#f2f5f7"
  readonly property color recordColor: "#e8413a"
  readonly property string hudFont: Style.font.family


  // The card is a fixed 500x250 plaque; the HUD sizes itself from its width.
  readonly property real cardWidth: 500
  readonly property real cardHeight: 250
  readonly property real hudScale: card.width / 720


  // ------------------------------------------------------------- lifecycle

  // `{"settings": true}` opens straight onto the settings face, which is how
  // the panel is driven from a script:
  //   omarchy-shell shell summon mib-vlog '{"settings":true}'
  function open(payloadJson) {
    var payload = ({})
    try {
      if (payloadJson) payload = JSON.parse(payloadJson) || ({})
    } catch (e) {
      payload = ({})
    }
    root.settingsOpen = payload.settings === true
    root.opened = true
    if (!root.settingsOpen) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Closing the panel ends the take and saves it.
  function close() {
    recording.stop()
    root.opened = false
    root.settingsOpen = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  // Starts or stops a take while the panel is open, for a keybinding:
  //   omarchy-shell shell call mib-vlog toggleRecording ""
  function toggleRecording() {
    if (!root.opened) return "closed"
    recording.toggle()
    return recording.active ? "recording" : "standby"
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // --------------------------------------------------------------- camera

  MediaDevices { id: mediaDevices }

  // Laptop webcams usually report an unspecified position, so a front-facing
  // match is preferred but the default input is the honest fallback.
  readonly property var cameraDevice: {
    var inputs = mediaDevices.videoInputs || []
    for (var i = 0; i < inputs.length; i++)
      if (inputs[i] && inputs[i].position === CameraDevice.FrontFace) return inputs[i]
    return mediaDevices.defaultVideoInput
  }
  readonly property bool cameraAvailable: !!cameraDevice

  // Takes, and the recorder the session writes them through.
  Recording {
    id: recording
    store: store
    weather: weather
    hudSource: exportHud
  }

  CaptureSession {
    id: session
    videoOutput: preview
    // Video only: sound is recorded outside Qt (see Recording.qml).
    recorder: recording.recorder
    camera: Camera {
      id: camera
      cameraDevice: root.cameraDevice
      // Held on past the panel closing until the recorder has finished the
      // file, or the end of the take is cut off.
      active: (root.opened || recording.busy) && root.cameraAvailable
    }
  }

  // The bar's record dot lives in another component instance, so the
  // recording state reaches it through a small file in the runtime dir.
  readonly property string stateFile: Quickshell.env("XDG_RUNTIME_DIR") + "/mib-vlog.state"

  function publishState() {
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" > "$2"', "sh",
      recording.active ? "recording" : "standby", root.stateFile])
  }

  Connections {
    target: recording
    function onActiveChanged() { root.publishState() }
  }

  Component.onCompleted: publishState()


  // ---------------------------------------------------------------- window

  // ---------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "mib-vlog"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The dimmed backdrop (settings → Dim background). Clicking it closes
    // the panel either way.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, store.dimBackground ? 0.78 : 0)
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Q) { root.dismiss(); event.accepted = true }
      }
    }

    // Clicking anywhere — scrim or card — closes the panel, ending and
    // saving any take. With Tap to record on, the card has its own handler
    // (below) and only the scrim closes.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.dismiss()
    }

    // The recording card: a small plaque hanging from the top of the screen,
    // clear of the bar.
    Item {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(40 * (width / root.cardWidth))
      width: Math.min(root.cardWidth, parent.width - 40)
      height: width * root.cardHeight / root.cardWidth
      clip: true

      Rectangle { anchors.fill: parent; color: "#101114" }

      // Full width at the camera's own aspect, pinned to the card's bottom
      // edge: the 2:1 card clips the top of the picture only, the same crop
      // finalize.sh applies to a saved take.
      VideoOutput {
        id: preview
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: sourceRect.width > 0 ? width * sourceRect.height / sourceRect.width : width * 9 / 16
        fillMode: VideoOutput.PreserveAspectFit
        // Mirrored, so the vlogger sees themselves the way a mirror shows them.
        transform: Scale { xScale: -1; origin.x: card.width / 2 }
      }

      Text {
        anchors.centerIn: parent
        visible: !root.cameraAvailable
        text: "NO CAMERA DETECTED"
        color: root.hud
        opacity: 0.6
        font.family: root.hudFont
        font.pixelSize: Math.round(24 * root.hudScale)
        font.letterSpacing: Math.round(3 * root.hudScale)
      }

      // Tap to record: a click on the preview starts or stops a take rather
      // than falling through to the close-on-click behind the card. The
      // HUD's own controls sit above this and still take their clicks.
      MouseArea {
        anchors.fill: parent
        enabled: store.tapToRecord && root.cameraAvailable
        onClicked: recording.toggle()
      }

      Hud {
        anchors.fill: parent
        store: store
        weather: weather
        recording: recording
        cameraAvailable: root.cameraAvailable
        hudColor: root.hud
        recordColor: root.recordColor
        hudFont: root.hudFont
        onSettingsRequested: root.settingsOpen = true
      }

      // The settings face. It is opaque and sits above the feed, so opening
      // it covers the camera and the HUD without either knowing about it.
      Component {
        id: settingsComponent

        SettingsView {
          store: store
          weather: weather
          hudScale: root.hudScale
          hud: root.hud
          hudFont: root.hudFont
          onDone: root.settingsOpen = false
        }
      }

      Loader {
        anchors.fill: parent
        active: root.settingsOpen
        sourceComponent: settingsComponent
        onLoaded: item.forceActiveFocus()
      }

      // A hairline frame, to sell the "this is a recording feed" look.
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Math.max(1, Math.round(1.5 * root.hudScale))
        border.color: Qt.rgba(1, 1, 1, 0.12)
      }
    }

    // The overlay burned into a take: the same HUD at the video's size,
    // without the record marker or gear. It sits outside the window, where
    // it is never seen but still renders, so Recording can snapshot it.
    Hud {
      id: exportHud
      x: -width - 100
      width: 1280
      height: 640
      controls: false
      frame: true
      store: store
      weather: weather
      recording: recording
      hudColor: root.hud
      hudFont: root.hudFont
    }
  }
}
