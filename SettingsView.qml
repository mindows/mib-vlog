pragma ComponentBehavior: Bound

import QtQuick

// The settings face of the card. It replaces the camera view rather than
// floating over it, so the same 500x250 plaque holds either the feed or its
// own configuration.
//
// The fields are the HUD's own words: everything here is a label the feed
// prints, except the launch date, which is what sol counts from.
FocusScope {
  id: view

  required property var store
  required property var weather
  property real hudScale: 1
  property color hud: "#f2f5f7"
  property string hudFont: "monospace"

  signal done()

  // Row pitch, shared with the location dropdown that hangs below its row.
  readonly property int rowHeight: Math.round(24 * view.hudScale)

  // Scrolls the list just enough to show the row at `index`, for focus
  // moving by keyboard.
  function reveal(index) {
    var pitch = view.rowHeight + form.spacing
    var top = index * pitch
    var bottom = top + view.rowHeight
    if (top < scroller.contentY) scroller.contentY = top
    else if (bottom > scroller.contentY + scroller.height)
      scroller.contentY = bottom - scroller.height
  }

  Keys.onEscapePressed: view.done()

  readonly property var rows: [
    { key: "missionLabel", label: "Mission day", hint: "MISSION DAY" },
    { key: "solLabel", label: "Sol", hint: "SOL" },
    { key: "launchDate", label: "Launch date", hint: "YYYY-MM-DD" },
    { key: "locationName", label: "Location", hint: "CITY, STATE, COUNTRY", search: true },
    { key: "tempUnit", label: "Temp unit",
      choices: [{ value: "C", text: "°C" }, { value: "F", text: "°F" }] },
    { key: "habLabel", label: "Hab", hint: "HAB" },
    { key: "locationLabel", label: "Room", hint: "BUNKS" },
    { key: "logLabel", label: "Log entry", hint: "LOG ENTRY > WATNEY" },
    { key: "timeLabel", label: "Time", hint: "TIME" },
    { key: "outputDir", label: "Output folder", hint: "~/mib-vlogs" },
    { key: "noiseReduction", label: "Noise reduction",
      choices: [{ value: "true", text: "On" }, { value: "false", text: "Off" }] },
    { key: "mirrorVideo", label: "Mirror video",
      choices: [{ value: "true", text: "On" }, { value: "false", text: "Off" }] },
    { key: "dimBackground", label: "Dim background",
      choices: [{ value: "true", text: "On" }, { value: "false", text: "Off" }] },
    { key: "tapToRecord", label: "Tap to record",
      choices: [{ value: "true", text: "On" }, { value: "false", text: "Off" }] },
    { key: "transcribe", label: "Transcribe",
      choices: [{ value: "true", text: "On" }, { value: "false", text: "Off" }] },
    { key: "locationMetadata", label: "Location metadata",
      choices: [{ value: "true", text: "On" }, { value: "false", text: "Off" }] }
  ]

  function commit(key, value) {
    if (key === "launchDate") view.store.setLaunchDate(value)
    else if (key === "tempUnit") view.store.setTempUnit(value)
    else if (key === "noiseReduction") view.store.setNoiseReduction(value === "true")
    else if (key === "mirrorVideo") view.store.setMirrorVideo(value === "true")
    else if (key === "dimBackground") view.store.setDimBackground(value === "true")
    else if (key === "tapToRecord") view.store.setTapToRecord(value === "true")
    else if (key === "transcribe") view.store.setTranscribe(value === "true")
    else if (key === "locationMetadata") view.store.setLocationMetadata(value === "true")
    else if (key === "outputDir") view.store.setOutputDir(value)
    else view.store.setLabel(key, value)
  }

  // ------------------------------------------------------- location search

  // The location row is a search box, not a free-text label: what it holds
  // is only ever a place the geocoder returned, so the weather always has
  // coordinates to ask about.
  property var locationInput: null
  property int locationRow: -1
  property int highlighted: 0
  readonly property var suggestions: view.weather.suggestions
  readonly property bool suggesting: !!view.locationInput && view.locationInput.activeFocus
    && view.suggestions.length > 0

  function pick(index) {
    var place = view.suggestions[index]
    if (!place) return
    view.store.setLocation(place.name, place.latitude, place.longitude)
    view.endSearch()
  }

  // Leaving the box without picking puts the saved place back.
  function endSearch() {
    view.weather.clearSearch()
    view.highlighted = 0
    if (view.locationInput) view.locationInput.text = view.store.locationName
  }

  function commitLocation() {
    if (view.suggestions.length > 0) {
      view.pick(view.highlighted)
    } else if (view.locationInput && view.locationInput.text.trim() === "") {
      // An emptied box asks for a fresh guess from Wi-Fi and IP.
      view.weather.locate()
      view.endSearch()
    }
  }

  // Swallows the clicks that would otherwise close the panel: a form the
  // first click dismisses is a form nobody can fill in.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: view.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: "#0d0e11"
  }

  Text {
    id: title
    x: Math.round(26 * view.hudScale)
    y: Math.round(14 * view.hudScale)
    text: "Settings"
    color: view.hud
    font.family: view.hudFont
    font.pixelSize: Math.round(15 * view.hudScale)
    font.letterSpacing: Math.round(2 * view.hudScale)
    font.capitalization: Font.AllUppercase
  }

  // The rows scroll: the card is a fixed 2:1 plaque, and the list outgrew
  // it. The area stops above the gear's corner.
  Flickable {
    id: scroller
    x: title.x
    y: Math.round(33 * view.hudScale)
    width: parent.width - x * 2
    height: parent.height - y - Math.round(30 * view.hudScale)
    contentHeight: form.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // A moved list leaves the location suggestions stranded; close them.
    onContentYChanged: if (view.suggesting) view.endSearch()

    Column {
      id: form
      width: scroller.width
      spacing: Math.round(3 * view.hudScale)

      Repeater {
        model: view.rows

        delegate: Item {
          id: row
          required property var modelData
          required property int index

          width: form.width
          height: view.rowHeight

          Text {
            id: rowLabel
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(150 * view.hudScale)
            text: row.modelData.label
            color: view.hud
            opacity: 0.6
            font.family: view.hudFont
            font.pixelSize: Math.round(11 * view.hudScale)
            font.letterSpacing: Math.round(1.5 * view.hudScale)
            font.capitalization: Font.AllUppercase
          }

          readonly property bool isChoice: !!row.modelData.choices

          // A pick-one row: the options side by side, the chosen one boxed.
          // Tab reaches it like a field; arrows or space switch it.
          Row {
            id: choice
            visible: row.isChoice
            anchors { left: rowLabel.right; verticalCenter: parent.verticalCenter }
            spacing: Math.round(6 * view.hudScale)
            activeFocusOnTab: row.isChoice
          onActiveFocusChanged: if (activeFocus) view.reveal(row.index)

            readonly property string current: row.isChoice ? String(view.store[row.modelData.key]) : ""

            function step() {
              var options = row.modelData.choices
              var index = 0
              for (var i = 0; i < options.length; i++) if (options[i].value === choice.current) index = i
              view.commit(row.modelData.key, options[(index + 1) % options.length].value)
            }

            Keys.onSpacePressed: choice.step()
            Keys.onLeftPressed: choice.step()
            Keys.onRightPressed: choice.step()

            Repeater {
              model: row.isChoice ? row.modelData.choices : []

              delegate: Rectangle {
                id: choiceOption
                required property var modelData

                readonly property bool chosen: choiceOption.modelData.value === choice.current

                width: Math.max(Math.round(30 * view.hudScale), optionText.implicitWidth + Math.round(12 * view.hudScale))
                height: Math.round(18 * view.hudScale)
                color: choiceOption.chosen ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, choiceOption.chosen && choice.activeFocus ? 0.75
                  : (choiceOption.chosen ? 0.4 : 0.15))

                Text {
                  id: optionText
                  anchors.centerIn: parent
                  text: choiceOption.modelData.text
                  color: view.hud
                  opacity: choiceOption.chosen ? 1 : 0.5
                  font.family: view.hudFont
                  font.pixelSize: Math.round(12 * view.hudScale)
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    choice.forceActiveFocus()
                    view.commit(row.modelData.key, choiceOption.modelData.value)
                  }
                }
              }
            }
          }

          // A hairline that lights up on focus, instead of a boxed control —
          // the HUD has no chrome anywhere else.
          Rectangle {
            visible: !row.isChoice
            anchors { left: rowLabel.right; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: Math.round(3 * view.hudScale)
            height: Math.max(1, Math.round(1 * view.hudScale))
            color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.75 : 0.2)
          }

          TextInput {
            id: input
            visible: !row.isChoice
            enabled: !row.isChoice
            anchors {
              left: rowLabel.right
              right: parent.right
              verticalCenter: parent.verticalCenter
            }
            activeFocusOnTab: true
            focus: row.index === 0
            text: view.store[row.modelData.key]
            color: view.hud
            selectionColor: Qt.rgba(1, 1, 1, 0.3)
            selectedTextColor: view.hud
            font.family: view.hudFont
            font.pixelSize: Math.round(13 * view.hudScale)
            clip: true

            readonly property bool isSearch: row.modelData.search === true

            Component.onCompleted: if (isSearch) {
              view.locationInput = input
              view.locationRow = row.index
            }

            onTextEdited: if (isSearch) {
              view.highlighted = 0
              view.weather.search(text)
            }
            onActiveFocusChanged: {
            if (activeFocus) view.reveal(row.index)
            else if (isSearch) view.endSearch()
          }
            onEditingFinished: if (!isSearch) view.commit(row.modelData.key, text)

            Keys.onReturnPressed: isSearch ? view.commitLocation() : view.commit(row.modelData.key, text)
            Keys.onEnterPressed: isSearch ? view.commitLocation() : view.commit(row.modelData.key, text)
            Keys.onDownPressed: function(event) {
              if (isSearch && view.suggesting)
                view.highlighted = Math.min(view.suggestions.length - 1, view.highlighted + 1)
              else event.accepted = false
            }
            Keys.onUpPressed: function(event) {
              if (isSearch && view.suggesting) view.highlighted = Math.max(0, view.highlighted - 1)
              else event.accepted = false
            }
            // Esc backs out of the suggestions first, and only then out of
            // settings.
            Keys.onEscapePressed: function(event) {
              if (isSearch && (view.suggesting || text !== view.store.locationName)) view.endSearch()
              else event.accepted = false
            }

            Text {
              anchors.fill: parent
              visible: input.text === ""
              text: row.modelData.hint || ""
              color: view.hud
              opacity: 0.25
              font: input.font
            }
          }
        }
      }
    }
  }

  // Where the list is: a hairline along the right edge, shown only when
  // there is more than fits.
  Rectangle {
    visible: scroller.contentHeight > scroller.height
    x: scroller.x + scroller.width + Math.round(6 * view.hudScale)
    y: scroller.y + scroller.visibleArea.yPosition * scroller.height
    width: Math.max(1, Math.round(2 * view.hudScale))
    height: scroller.visibleArea.heightRatio * scroller.height
    radius: width / 2
    color: Qt.rgba(1, 1, 1, 0.35)
  }

  Text {
    id: gear
    anchors {
      right: parent.right
      rightMargin: Math.round(26 * view.hudScale)
      bottom: parent.bottom
      bottomMargin: Math.round(12 * view.hudScale)
    }
    text: "󰒓"
    color: view.hud
    opacity: gearMouse.containsMouse ? 1.0 : 0.7
    font.family: view.hudFont
    font.pixelSize: Math.round(16 * view.hudScale)

    MouseArea {
      id: gearMouse
      anchors.centerIn: parent
      width: Math.max(parent.width, Math.round(26 * view.hudScale))
      height: Math.max(parent.height, Math.round(26 * view.hudScale))
      hoverEnabled: true
      onClicked: view.done()
    }
  }

  Rectangle {
    id: dropdown
    visible: view.suggesting
    x: scroller.x + Math.round(150 * view.hudScale)
    y: scroller.y + (view.locationRow + 1) * (view.rowHeight + form.spacing) - scroller.contentY
    width: scroller.width - Math.round(150 * view.hudScale)
    height: suggestionList.height + Math.round(8 * view.hudScale)
    color: "#17191e"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)

    Column {
      id: suggestionList
      x: Math.round(4 * view.hudScale)
      y: Math.round(4 * view.hudScale)
      width: parent.width - x * 2

      Repeater {
        model: view.suggestions

        delegate: Rectangle {
          id: option
          required property var modelData
          required property int index

          width: suggestionList.width
          height: Math.round(22 * view.hudScale)
          color: option.index === view.highlighted ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

          Text {
            anchors { left: parent.left; leftMargin: Math.round(6 * view.hudScale); right: parent.right
                      verticalCenter: parent.verticalCenter }
            text: option.modelData.name
            elide: Text.ElideRight
            color: view.hud
            font.family: view.hudFont
            font.pixelSize: Math.round(12 * view.hudScale)
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: view.highlighted = option.index
            onClicked: view.pick(option.index)
          }
        }
      }
    }
  }

  // Read-only counters, so the two numbers the feed derives are visible
  // where the things that drive them are edited. They share the title's
  // line, leaving the rest of the card to the rows.
  Row {
    anchors {
      right: parent.right
      rightMargin: title.x
      verticalCenter: title.verticalCenter
    }
    spacing: Math.round(16 * view.hudScale)

    Text {
      text: "Sol " + view.store.sol
      color: view.hud
      opacity: 0.55
      font.family: view.hudFont
      font.pixelSize: Math.round(11 * view.hudScale)
      font.letterSpacing: Math.round(1.5 * view.hudScale)
      font.capitalization: Font.AllUppercase
    }

    Text {
      text: view.weather.searching ? "Searching" : (view.weather.status || view.weather.label)
      color: view.hud
      opacity: 0.55
      font.family: view.hudFont
      font.pixelSize: Math.round(11 * view.hudScale)
      font.letterSpacing: Math.round(1.5 * view.hudScale)
      font.capitalization: Font.AllUppercase
    }

    Text {
      text: "Log entries " + view.store.entryCount
      color: view.hud
      opacity: 0.55
      font.family: view.hudFont
      font.pixelSize: Math.round(11 * view.hudScale)
      font.letterSpacing: Math.round(1.5 * view.hudScale)
      font.capitalization: Font.AllUppercase
    }
  }
}
