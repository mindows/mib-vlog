pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "Plugin.js" as Plugin

// The mission HUD: every mark drawn over the camera — the readouts and their
// rings, the side rules, the edge falloff, and (optionally) the record marker
// and settings gear.
//
// It lays itself out from its own width against a 720px reference frame, so
// the same component draws the 500x250 card on screen and, off screen, the
// full-resolution overlay burned into a saved take.
Item {
  id: hud

  required property var store
  required property var weather
  required property var recording

  // The record marker and gear. The on-screen card has them; the overlay
  // burned into a take does not.
  property bool controls: true
  // A faint hairline around the frame.
  property bool frame: false
  property bool cameraAvailable: true

  property color hudColor: "#f2f5f7"
  property color recordColor: Plugin.recordColor
  property string hudFont: "monospace"

  signal settingsRequested()

  readonly property real hudScale: width / 720

  // The current temperature in the chosen scale, one decimal like the rest
  // of the readouts, and where it sits on that scale's gauge: -10..50 °C,
  // 0..130 °F.
  readonly property real temperature: hud.store.tempUnit === "F"
    ? hud.weather.temperatureC * 9 / 5 + 32 : hud.weather.temperatureC
  readonly property string temperatureText: isNaN(temperature) ? "--" : temperature.toFixed(1)
  readonly property real temperatureFill: {
    if (isNaN(temperature)) return 0
    var low = hud.store.tempUnit === "F" ? 0 : -10
    var high = hud.store.tempUnit === "F" ? 130 : 50
    return Math.max(0, Math.min(1, (temperature - low) / (high - low)))
  }

  // Up while the air is within the US AQI's good and moderate bands (0-100),
  // down once it reaches "unhealthy for sensitive groups" and beyond.
  readonly property string airQualityGlyph: isNaN(hud.weather.aqi) ? ""
    : (hud.weather.aqi <= 100 ? "󰔓" : "󰔑")

  // Log entries read as an index on the feed, so they keep three digits.
  readonly property string paddedEntry: {
    var text = String(Math.max(0, hud.store.entryCount))
    while (text.length < 3) text = "0" + text
    return text
  }

  // ----------------------------------------------------------- HUD pieces

  component HudCaption: Text {
    textFormat: Text.PlainText
    color: hud.hudColor
    opacity: 0.72
    font.family: hud.hudFont
    font.pixelSize: Math.round(12 * hud.hudScale)
    font.letterSpacing: Math.round(2 * hud.hudScale)
    font.capitalization: Font.AllUppercase
  }

  component HudReadout: Text {
    textFormat: Text.PlainText
    color: hud.hudColor
    opacity: 0.9
    font.family: hud.hudFont
    font.pixelSize: Math.round(24 * hud.hudScale)
    font.letterSpacing: Math.round(1 * hud.hudScale)
  }

  // The pair of hairlines running down the inside of the frame, each with a
  // centering tick — the film's feed has them, and they read as the edge of a
  // viewfinder rather than as another readout. They sit inside the frame but
  // outside the text margin, so they never cross the HUD.
  component EdgeGuide: Item {
    id: guide
    property bool fromRight: false

    width: Math.max(1, Math.round(1 * hud.hudScale))

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(1, 1, 1, 0.45)
    }

    Rectangle {
      y: Math.round(parent.height * 0.55)
      // The tick points inward, away from the nearer frame edge.
      x: guide.fromRight ? guide.width - width : 0
      width: Math.round(12 * hud.hudScale)
      height: Math.max(1, Math.round(1 * hud.hudScale))
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
    readonly property real strokeWidth: Math.max(1, Math.round(1.2 * hud.hudScale))
    readonly property real arcWidth: Math.max(1.5, 2 * hud.hudScale)

    spacing: Math.round(10 * hud.hudScale)

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(ringBlock.naturalTextWidth, ringBlock.textWidth)
      spacing: Math.round(-5 * hud.hudScale)

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
        border.color: Qt.rgba(hud.hudColor.r, hud.hudColor.g, hud.hudColor.b, ringBlock.gauge ? 0.28 : 0.55)
      }

      Shape {
        anchors.fill: parent
        visible: ringBlock.gauge && ringBlock.fill > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Qt.rgba(hud.hudColor.r, hud.hudColor.g, hud.hudColor.b, 0.95)
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
        textFormat: Text.PlainText
        id: ringSymbol
        x: Math.round(ring.width / 2
          - (symbolInk.tightBoundingRect.x + symbolInk.tightBoundingRect.width / 2))
        y: Math.round(ring.height / 2
          - (ringSymbol.baselineOffset + symbolInk.tightBoundingRect.y + symbolInk.tightBoundingRect.height / 2))
        text: ringBlock.symbol
        color: hud.hudColor
        opacity: 0.9
        font.family: hud.hudFont
        font.pixelSize: Math.round(ring.width * 0.5)
      }
    }
  }

  // A boxed cell. The header's sol counter is one cell holding both words, so
  // "SOL 19" reads as a single plate rather than two adjacent chips.
  component HudCell: Rectangle {
    property alias text: cellText.text
    color: Qt.rgba(1, 1, 1, 0.14)
    implicitWidth: cellText.implicitWidth + Math.round(22 * hud.hudScale)
    implicitHeight: Math.round(28 * hud.hudScale)

    Text {
      textFormat: Text.PlainText
      id: cellText
      anchors.centerIn: parent
      color: hud.hudColor
      font.family: hud.hudFont
      font.pixelSize: Math.round(18 * hud.hudScale)
      font.letterSpacing: Math.round(2.5 * hud.hudScale)
      font.capitalization: Font.AllUppercase
    }
  }

  // ---------------------------------------------------------------- layout

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
      // In pixels, so it scales with the HUD: a 1280px export keeps the
      // same halo as the 500px card.
      blurMax: Math.max(2, Math.min(64, Math.round(11.5 * hud.hudScale)))
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
    }

    // ------------------------------------------------------ header (left)

    Column {
      id: header
      x: Math.round(26 * hud.hudScale)
      y: Math.round(16 * hud.hudScale)
      spacing: Math.round(6 * hud.hudScale)

      HudCaption {
        text: hud.store.missionLabel
        opacity: 0.85
        font.pixelSize: Math.round(15 * hud.hudScale)
      }

      HudCell { text: hud.store.solLabel + " " + hud.store.sol }
    }

    // ------------------------------------------- environment stack (left)

    Column {
      id: stack
      x: header.x
      y: Math.round(hud.height * 0.25)
      spacing: Math.round(10 * hud.hudScale)

      readonly property real ringTextWidth: Math.max(weatherBlock.naturalTextWidth,
        tempBlock.naturalTextWidth, aqiBlock.naturalTextWidth)

      RingBlock {
        id: weatherBlock
        textWidth: stack.ringTextWidth
        caption: "Weather"
        value: hud.weather.status || hud.weather.label || "--"
        symbol: hud.weather.glyph
      }

      RingBlock {
        id: tempBlock
        textWidth: stack.ringTextWidth
        caption: "Temp"
        value: hud.temperatureText
        symbol: hud.store.tempUnit
        fill: hud.temperatureFill
      }

      RingBlock {
        id: aqiBlock
        textWidth: stack.ringTextWidth
        caption: "AQI"
        value: isNaN(hud.weather.aqi) ? "--" : String(Math.round(hud.weather.aqi))
        symbol: hud.airQualityGlyph
        fill: isNaN(hud.weather.aqi) ? 0 : Math.max(0, Math.min(1, hud.weather.aqi / 500))
      }

      HudCaption {
        // A little extra air above: the rings are taller than the text
        // they sit beside.
        topPadding: Math.round(5 * hud.hudScale)
        text: "Environment"
        opacity: 0.6
      }
    }

    // ----------------------------------------------------- header (right)

    Column {
      anchors { right: parent.right; rightMargin: Math.round(26 * hud.hudScale) }
      y: Math.round(18 * hud.hudScale)
      spacing: Math.round(7 * hud.hudScale)

      HudCaption {
        anchors.right: parent.right
        text: hud.store.timeLabel + " " + hud.store.clock
        opacity: 0.6
      }

      HudCaption {
        anchors.right: parent.right
        text: hud.store.logLabel + " #" + hud.paddedEntry
        opacity: 0.75
      }
    }

    // ------------------------------------------------------ footer (left)

    Column {
      id: footer
      x: header.x
      anchors { bottom: parent.bottom; bottomMargin: Math.round(20 * hud.hudScale) }
      // Negative: HAB's line box carries descender room its capitals
      // never use, so it can sit closer to the line below.
      spacing: Math.round(-1 * hud.hudScale)

      Row {
        spacing: Math.round(9 * hud.hudScale)

        Text {
          textFormat: Text.PlainText
          text: hud.store.habLabel
          color: hud.hudColor
          font.family: hud.hudFont
          font.pixelSize: Math.round(28 * hud.hudScale)
          font.bold: true
          font.letterSpacing: Math.round(2 * hud.hudScale)
        }

        Text {
          textFormat: Text.PlainText
          text: hud.store.locationLabel
          color: hud.hudColor
          opacity: 0.85
          font.family: hud.hudFont
          font.pixelSize: Math.round(28 * hud.hudScale)
          font.letterSpacing: Math.round(4 * hud.hudScale)
        }
      }

      HudCaption {
        text: [hud.store.hostname, hud.store.locationName].filter(function(part) { return !!part }).join(" | ")
        opacity: 0.45
        font.pixelSize: Math.round(11 * hud.hudScale)
      }
    }

    // ----------------------------------------------------- record marker

    Row {
      visible: hud.controls
      anchors {
        right: parent.right
        rightMargin: Math.round(26 * hud.hudScale)
        bottom: parent.bottom
        bottomMargin: Math.round(22 * hud.hudScale)
      }
      spacing: Math.round(7 * hud.hudScale)

      // The dot and its word are one button: click to start a take,
      // click again to stop it.
      Item {
        id: recordButton
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: recordRow.implicitWidth
        implicitHeight: recordRow.implicitHeight

        // Faded at standby; blinking slowly while a take is running.
        property real blink: 1.0

        SequentialAnimation on blink {
          running: hud.recording.active
          loops: Animation.Infinite
          NumberAnimation { to: 0.15; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }

        Row {
          id: recordRow
          spacing: Math.round(7 * hud.hudScale)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(11 * hud.hudScale)
            height: width
            radius: width / 2
            color: hud.recordColor
            opacity: hud.recording.active ? recordButton.blink : 0.35
          }

          HudCaption {
            anchors.verticalCenter: parent.verticalCenter
            text: hud.recording.active ? "Recording" : (hud.recording.error ? "Error" : "Standby")
            opacity: hud.recording.active ? 0.95 : 0.7
          }
        }

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Math.round(4 * hud.hudScale)
          enabled: hud.cameraAvailable
          onClicked: hud.recording.toggle()
        }
      }

      // The one control on the feed: it swaps the card over to settings.
      Text {
        textFormat: Text.PlainText
        id: gear
        anchors.verticalCenter: parent.verticalCenter
        text: "󰒓"
        color: hud.hudColor
        opacity: gearMouse.containsMouse ? 1.0 : 0.7
        font.family: hud.hudFont
        font.pixelSize: Math.round(16 * hud.hudScale)

        MouseArea {
          id: gearMouse
          anchors.centerIn: parent
          // A 16px glyph is a small target; the hit area is padded out to
          // something a pointer can actually land on.
          width: Math.max(parent.width, Math.round(26 * hud.hudScale))
          height: Math.max(parent.height, Math.round(26 * hud.hudScale))
          hoverEnabled: true
          onClicked: hud.settingsRequested()
        }
      }
    }

    // Both rules run the full height of the HUD: from the top of the first
    // line of text to the bottom of the last.
    EdgeGuide {
      x: Math.round(17 * hud.hudScale)
      y: header.y
      height: footer.y + footer.height - header.y
    }

    EdgeGuide {
      fromRight: true
      x: hud.width - Math.round(17 * hud.hudScale) - width
      y: header.y
      height: footer.y + footer.height - header.y
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: hud.frame
    color: "transparent"
    border.width: Math.max(1, Math.round(1.5 * hud.hudScale))
    border.color: Qt.rgba(1, 1, 1, 0.12)
  }
}
