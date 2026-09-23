pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import QtQuick.Effects
import QtQuick.Shapes
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

  // The current temperature in the chosen scale, one decimal like the rest
  // of the readouts, and where it sits on that scale's gauge: -10..50 °C,
  // 0..130 °F.
  readonly property real temperature: store.tempUnit === "F"
    ? weather.temperatureC * 9 / 5 + 32 : weather.temperatureC
  readonly property string temperatureText: isNaN(temperature) ? "--" : temperature.toFixed(1)
  readonly property real temperatureFill: {
    if (isNaN(temperature)) return 0
    var low = store.tempUnit === "F" ? 0 : -10
    var high = store.tempUnit === "F" ? 130 : 50
    return Math.max(0, Math.min(1, (temperature - low) / (high - low)))
  }

  // Up while the air is within the US AQI's good and moderate bands (0-100),
  // down once it reaches "unhealthy for sensitive groups" and beyond.
  readonly property string airQualityGlyph: isNaN(weather.aqi) ? ""
    : (weather.aqi <= 100 ? "󰔓" : "󰔑")

  // Log entries read as an index on the feed, so they keep three digits.
  readonly property string paddedEntry: {
    var text = String(Math.max(0, store.entryCount))
    while (text.length < 3) text = "0" + text
    return text
  }

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

  function close() {
    root.opened = false
    root.settingsOpen = false
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

  // The card is a fixed 500x250 plaque, but every HUD size is still expressed
  // against a 720px-wide reference frame, so shrinking the card on a narrow
  // screen shrinks the HUD with it instead of overflowing it.
  readonly property real cardWidth: 500
  readonly property real cardHeight: 250
  readonly property real hudScale: card.width / 720

  component HudCaption: Text {
    color: root.hud
    opacity: 0.72
    font.family: root.hudFont
    font.pixelSize: Math.round(12 * root.hudScale)
    font.letterSpacing: Math.round(2 * root.hudScale)
    font.capitalization: Font.AllUppercase
  }

  component HudReadout: Text {
    color: root.hud
    opacity: 0.9
    font.family: root.hudFont
    font.pixelSize: Math.round(24 * root.hudScale)
    font.letterSpacing: Math.round(1 * root.hudScale)
  }

  // The pair of hairlines running down the inside of the frame, each with a
  // centering tick — the film's feed has them, and they read as the edge of a
  // viewfinder rather than as another readout. They sit inside the frame but
  // outside the text margin, so they never cross the HUD.
  component EdgeGuide: Item {
    id: guide
    property bool fromRight: false

    width: Math.max(1, Math.round(1 * root.hudScale))

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(1, 1, 1, 0.45)
    }

    Rectangle {
      y: Math.round(parent.height * 0.55)
      // The tick points inward, away from the nearer frame edge.
      x: guide.fromRight ? guide.width - width : 0
      width: Math.round(12 * root.hudScale)
      height: Math.max(1, Math.round(1 * root.hudScale))
      color: Qt.rgba(1, 1, 1, 0.45)
    }
  }

  // A readout whose circle is as tall as its caption and value together and
  // holds a symbol rather than a unit: the weather icon, or the temperature
  // scale. With `fill` set, the circle doubles as a gauge, its outline lit
  // clockwise from twelve o'clock in proportion.
  component RingBlock: Row {
    id: ringBlock
    property string caption: ""
    property string value: ""
    property string symbol: ""
    // 0..1 lights that much of the outline; negative means no gauge.
    property real fill: -1
    // Stacked blocks share the widest caption/value width, so their circles
    // line up in one column instead of stepping in with each value's width.
    property real textWidth: 0
    readonly property real naturalTextWidth: Math.max(ringCaption.implicitWidth, ringValue.implicitWidth)

    readonly property bool gauge: fill >= 0
    readonly property real strokeWidth: Math.max(1, Math.round(1.2 * root.hudScale))
    readonly property real arcWidth: Math.max(1.5, 2 * root.hudScale)

    spacing: Math.round(10 * root.hudScale)

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(ringBlock.naturalTextWidth, ringBlock.textWidth)
      spacing: Math.round(-5 * root.hudScale)

      HudCaption { id: ringCaption; text: ringBlock.caption }

      HudReadout {
        id: ringValue
        text: ringBlock.value
        font.capitalization: Font.AllUppercase
      }
    }

    Item {
      id: ring
      anchors.verticalCenter: parent.verticalCenter
      width: ringCaption.implicitHeight + ringValue.implicitHeight
      height: width

      // A gauge dims its track so the lit arc reads against it.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: ringBlock.strokeWidth
        border.color: Qt.rgba(root.hud.r, root.hud.g, root.hud.b, ringBlock.gauge ? 0.28 : 0.55)
      }

      Shape {
        anchors.fill: parent
        visible: ringBlock.gauge && ringBlock.fill > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Qt.rgba(root.hud.r, root.hud.g, root.hud.b, 0.95)
          strokeWidth: ringBlock.arcWidth
          fillColor: "transparent"
          capStyle: ShapePath.FlatCap

          PathAngleArc {
            centerX: ring.width / 2
            centerY: ring.height / 2
            radiusX: (ring.width - ringBlock.arcWidth) / 2
            radiusY: radiusX
            startAngle: -90
            sweepAngle: 360 * Math.min(1, ringBlock.fill)
          }
        }
      }

      // Glyphs sit off-centre in their em box, and each one differently, so
      // the symbol is centred on its inked bounds rather than its line box.
      TextMetrics {
        id: symbolInk
        font: ringSymbol.font
        text: ringSymbol.text
      }

      Text {
        id: ringSymbol
        x: Math.round(ring.width / 2
          - (symbolInk.tightBoundingRect.x + symbolInk.tightBoundingRect.width / 2))
        y: Math.round(ring.height / 2
          - (ringSymbol.baselineOffset + symbolInk.tightBoundingRect.y + symbolInk.tightBoundingRect.height / 2))
        text: ringBlock.symbol
        color: root.hud
        opacity: 0.9
        font.family: root.hudFont
        font.pixelSize: Math.round(ring.width * 0.5)
      }
    }
  }

  // A boxed cell. The header's sol counter is one cell holding both words, so
  // "SOL 19" reads as a single plate rather than two adjacent chips.
  component HudCell: Rectangle {
    property alias text: cellText.text
    color: Qt.rgba(1, 1, 1, 0.14)
    implicitWidth: cellText.implicitWidth + Math.round(22 * root.hudScale)
    implicitHeight: Math.round(28 * root.hudScale)

    Text {
      id: cellText
      anchors.centerIn: parent
      color: root.hud
      font.family: root.hudFont
      font.pixelSize: Math.round(18 * root.hudScale)
      font.letterSpacing: Math.round(2.5 * root.hudScale)
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

      // Every HUD mark lives in one layer so a single soft shadow can sit
      // behind all of it: a dark halo that keeps the text legible over a
      // bright frame without boxing anything in.
      Item {
        id: hudLayer
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: "black"
          shadowOpacity: 0.9
          shadowBlur: 0.5
          blurMax: 8
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 0
        }

        // ------------------------------------------------------ header (left)

        Column {
          id: header
          x: Math.round(26 * root.hudScale)
          y: Math.round(16 * root.hudScale)
          spacing: Math.round(6 * root.hudScale)

          HudCaption {
            text: store.missionLabel
            opacity: 0.85
            font.pixelSize: Math.round(15 * root.hudScale)
          }

          HudCell { text: store.solLabel + " " + store.sol }
        }

        // ------------------------------------------- environment stack (left)

        Column {
          id: stack
          x: header.x
          y: Math.round(card.height * 0.25)
          spacing: Math.round(10 * root.hudScale)

          readonly property real ringTextWidth: Math.max(weatherBlock.naturalTextWidth,
            tempBlock.naturalTextWidth, aqiBlock.naturalTextWidth)

          RingBlock {
            id: weatherBlock
            textWidth: stack.ringTextWidth
            caption: "Weather"
            value: weather.status || weather.label || "--"
            symbol: weather.glyph
          }

          RingBlock {
            id: tempBlock
            textWidth: stack.ringTextWidth
            caption: "Temp"
            value: root.temperatureText
            symbol: store.tempUnit
            fill: root.temperatureFill
          }

          RingBlock {
            id: aqiBlock
            textWidth: stack.ringTextWidth
            caption: "AQI"
            value: isNaN(weather.aqi) ? "--" : String(Math.round(weather.aqi))
            symbol: root.airQualityGlyph
            fill: isNaN(weather.aqi) ? 0 : Math.max(0, Math.min(1, weather.aqi / 500))
          }

          HudCaption {
            // A little extra air above: the rings are taller than the text
            // they sit beside.
            topPadding: Math.round(5 * root.hudScale)
            text: "Environment"
            opacity: 0.6
          }
        }

        // ----------------------------------------------------- header (right)

        Column {
          anchors { right: parent.right; rightMargin: Math.round(26 * root.hudScale) }
          y: Math.round(18 * root.hudScale)
          spacing: Math.round(7 * root.hudScale)

          HudCaption {
            anchors.right: parent.right
            text: store.timeLabel + " " + store.clock
            opacity: 0.6
          }

          HudCaption {
            anchors.right: parent.right
            text: store.logLabel + " #" + root.paddedEntry
            opacity: 0.75
          }
        }

        // ------------------------------------------------------ footer (left)

        Column {
          id: footer
          x: header.x
          anchors { bottom: parent.bottom; bottomMargin: Math.round(20 * root.hudScale) }
          // Negative: HAB's line box carries descender room its capitals
          // never use, so it can sit closer to the line below.
          spacing: Math.round(-1 * root.hudScale)

          Row {
            spacing: Math.round(9 * root.hudScale)

            Text {
              text: store.habLabel
              color: root.hud
              font.family: root.hudFont
              font.pixelSize: Math.round(28 * root.hudScale)
              font.bold: true
              font.letterSpacing: Math.round(2 * root.hudScale)
            }

            Text {
              text: store.locationLabel
              color: root.hud
              opacity: 0.85
              font.family: root.hudFont
              font.pixelSize: Math.round(28 * root.hudScale)
              font.letterSpacing: Math.round(4 * root.hudScale)
            }
          }

          HudCaption {
            text: [store.hostname, store.locationName].filter(function(part) { return !!part }).join(" | ")
            opacity: 0.45
            font.pixelSize: Math.round(11 * root.hudScale)
          }
        }

        // ----------------------------------------------------- record marker

        Row {
          anchors {
            right: parent.right
            rightMargin: Math.round(26 * root.hudScale)
            bottom: parent.bottom
            bottomMargin: Math.round(22 * root.hudScale)
          }
          spacing: Math.round(7 * root.hudScale)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(11 * root.hudScale)
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

          // The one control on the feed: it swaps the card over to settings.
          Text {
            id: gear
            anchors.verticalCenter: parent.verticalCenter
            text: "󰒓"
            color: root.hud
            opacity: gearMouse.containsMouse ? 1.0 : 0.7
            font.family: root.hudFont
            font.pixelSize: Math.round(16 * root.hudScale)

            MouseArea {
              id: gearMouse
              anchors.centerIn: parent
              // A 16px glyph is a small target; the hit area is padded out to
              // something a pointer can actually land on.
              width: Math.max(parent.width, Math.round(26 * root.hudScale))
              height: Math.max(parent.height, Math.round(26 * root.hudScale))
              hoverEnabled: true
              onClicked: root.settingsOpen = true
            }
          }
        }

        // Both rules run the full height of the HUD: from the top of the first
        // line of text to the bottom of the last.
        EdgeGuide {
          x: Math.round(17 * root.hudScale)
          y: header.y
          height: footer.y + footer.height - header.y
        }

        EdgeGuide {
          fromRight: true
          x: card.width - Math.round(17 * root.hudScale) - width
          y: header.y
          height: footer.y + footer.height - header.y
        }
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
  }
}
