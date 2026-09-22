pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons

// MIB Vlog — the recording surface.
//
// A fullscreen layer holds one 16:9 card: the front camera fills it as the
// background, and a translucent mission-status HUD sits on top. The HUD
// readouts are deliberately static for now; recording is not implemented, so
// nothing here writes to disk or touches the microphone.
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

  readonly property string pluginId: (manifest && manifest.id) || "mib-vlog"
  readonly property color hud: "#f2f5f7"
  readonly property color recordColor: "#e8413a"
  readonly property string hudFont: Style.font.family

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
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

  CaptureSession {
    id: session
    videoOutput: preview
    camera: Camera {
      id: camera
      cameraDevice: root.cameraDevice
      active: root.opened && root.cameraAvailable
    }
  }

  // ----------------------------------------------------------- HUD pieces

  // Every size is expressed against a 1280px-wide card so the HUD keeps its
  // proportions on a 1080p laptop panel and on a 4K monitor alike.
  readonly property real hudScale: card.width / 1280

  component HudCaption: Text {
    color: root.hud
    opacity: 0.72
    font.family: root.hudFont
    font.pixelSize: Math.round(13 * root.hudScale)
    font.letterSpacing: Math.round(2.4 * root.hudScale)
    font.capitalization: Font.AllUppercase
  }

  component HudReadout: Text {
    color: root.hud
    opacity: 0.9
    font.family: root.hudFont
    font.pixelSize: Math.round(30 * root.hudScale)
    font.letterSpacing: Math.round(1 * root.hudScale)
  }

  // Label over value, with the unit in a hairline circle beside the number —
  // the pressure/oxygen/temperature stack down the left edge.
  component StatBlock: Column {
    property alias caption: captionText.text
    property alias value: valueText.text
    property string unit: ""
    spacing: Math.round(2 * root.hudScale)

    HudCaption { id: captionText }

    Row {
      spacing: Math.round(14 * root.hudScale)

      HudReadout { id: valueText; anchors.verticalCenter: parent.verticalCenter }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(30 * root.hudScale)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Math.round(1.2 * root.hudScale))
        border.color: Qt.rgba(root.hud.r, root.hud.g, root.hud.b, 0.55)

        Text {
          anchors.centerIn: parent
          text: unit
          color: root.hud
          opacity: 0.8
          font.family: root.hudFont
          font.pixelSize: Math.round(12 * root.hudScale)
        }
      }
    }
  }

  // A boxed cell, as used by the SOL counter in the header.
  component HudCell: Rectangle {
    property alias text: cellText.text
    color: Qt.rgba(1, 1, 1, 0.14)
    implicitWidth: cellText.implicitWidth + Math.round(26 * root.hudScale)
    implicitHeight: Math.round(40 * root.hudScale)

    Text {
      id: cellText
      anchors.centerIn: parent
      color: root.hud
      font.family: root.hudFont
      font.pixelSize: Math.round(26 * root.hudScale)
      font.letterSpacing: Math.round(2 * root.hudScale)
      font.capitalization: Font.AllUppercase
    }
  }

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

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.78)
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

    // Clicking anywhere — scrim or card — closes the panel.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.dismiss()
    }

    // The 16:9 recording card, as large as the screen allows with a margin.
    Item {
      id: card
      anchors.centerIn: parent
      width: Math.min(parent.width * 0.92, (parent.height * 0.92) * 16 / 9)
      height: width * 9 / 16
      clip: true

      Rectangle { anchors.fill: parent; color: "#101114" }

      VideoOutput {
        id: preview
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
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

      // Edge falloff: the HUD text sits over the darkened top and bottom of
      // the frame rather than fighting the image for contrast.
      Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height * 0.45
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: parent.height * 0.45
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
        }
      }

      // ------------------------------------------------------ header (left)

      Column {
        id: header
        x: Math.round(40 * root.hudScale)
        y: Math.round(28 * root.hudScale)
        spacing: Math.round(8 * root.hudScale)

        HudCaption {
          text: "Mission Day"
          opacity: 0.85
          font.pixelSize: Math.round(17 * root.hudScale)
        }

        Row {
          spacing: Math.round(6 * root.hudScale)
          HudCell { text: "Sol" }
          HudCell { text: "19" }
        }
      }

      // ------------------------------------------- environment stack (left)

      Column {
        x: header.x
        y: Math.round(card.height * 0.30)
        spacing: Math.round(20 * root.hudScale)

        StatBlock { caption: "Pressure"; value: "12.48"; unit: "PSI" }
        StatBlock { caption: "Oxygen"; value: "20.79"; unit: "%" }
        StatBlock { caption: "Temp"; value: "21.14"; unit: "C" }

        HudCaption {
          text: "Environment"
          opacity: 0.6
        }
      }

      // ----------------------------------------------------- header (right)

      Column {
        anchors { right: parent.right; rightMargin: Math.round(40 * root.hudScale) }
        y: Math.round(30 * root.hudScale)
        spacing: Math.round(10 * root.hudScale)

        HudCaption {
          anchors.right: parent.right
          text: "Time 06 53"
          opacity: 0.6
        }

        HudCaption {
          anchors.right: parent.right
          text: "Log Entry > Watney #009"
          opacity: 0.75
        }
      }

      // ------------------------------------------------------ footer (left)

      Column {
        x: header.x
        anchors { bottom: parent.bottom; bottomMargin: Math.round(30 * root.hudScale) }
        spacing: Math.round(8 * root.hudScale)

        Row {
          spacing: Math.round(12 * root.hudScale)

          Text {
            text: "HAB"
            color: root.hud
            font.family: root.hudFont
            font.pixelSize: Math.round(38 * root.hudScale)
            font.bold: true
            font.letterSpacing: Math.round(2 * root.hudScale)
          }

          Text {
            text: "BUNKS"
            color: root.hud
            opacity: 0.85
            font.family: root.hudFont
            font.pixelSize: Math.round(38 * root.hudScale)
            font.letterSpacing: Math.round(6 * root.hudScale)
          }
        }

        HudCaption {
          text: "Connected:0022213Ø2EWBVC-2-4002060-26-3"
          opacity: 0.45
          font.pixelSize: Math.round(10 * root.hudScale)
        }
      }

      // ----------------------------------------------------- record marker

      Row {
        anchors {
          right: parent.right
          rightMargin: Math.round(40 * root.hudScale)
          bottom: parent.bottom
          bottomMargin: Math.round(34 * root.hudScale)
        }
        spacing: Math.round(10 * root.hudScale)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(12 * root.hudScale)
          height: width
          radius: width / 2
          color: root.recordColor
          opacity: 0.85
        }

        HudCaption {
          anchors.verticalCenter: parent.verticalCenter
          text: "Standby"
          opacity: 0.7
        }
      }

      // A hairline frame, to sell the "this is a recording feed" look.
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Math.max(1, Math.round(1.5 * root.hudScale))
        border.color: Qt.rgba(1, 1, 1, 0.12)
      }
    }
  }
}
