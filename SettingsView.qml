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
  property real hudScale: 1
  property color hud: "#f2f5f7"
  property string hudFont: "monospace"

  signal done()

  Keys.onEscapePressed: view.done()

  readonly property var rows: [
    { key: "missionLabel", label: "Mission day", hint: "MISSION DAY" },
    { key: "solLabel", label: "Sol", hint: "SOL" },
    { key: "launchDate", label: "Launch date", hint: "YYYY-MM-DD" },
    { key: "habLabel", label: "Hab", hint: "HAB" },
    { key: "locationLabel", label: "Location", hint: "BUNKS" },
    { key: "logLabel", label: "Log entry", hint: "LOG ENTRY > WATNEY" },
    { key: "timeLabel", label: "Time", hint: "TIME" },
    { key: "connectedLabel", label: "Connected", hint: "CONNECTED" }
  ]

  function commit(key, value) {
    if (key === "launchDate") view.store.setLaunchDate(value)
    else view.store.setLabel(key, value)
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

  Column {
    id: form
    x: title.x
    y: Math.round(42 * view.hudScale)
    width: parent.width - x * 2
    spacing: Math.round(3 * view.hudScale)

    Repeater {
      model: view.rows

      delegate: Item {
        id: row
        required property var modelData
        required property int index

        width: form.width
        height: Math.round(24 * view.hudScale)

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

        // A hairline that lights up on focus, instead of a boxed control —
        // the HUD has no chrome anywhere else.
        Rectangle {
          anchors { left: rowLabel.right; right: parent.right; bottom: parent.bottom }
          anchors.bottomMargin: Math.round(3 * view.hudScale)
          height: Math.max(1, Math.round(1 * view.hudScale))
          color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.75 : 0.2)
        }

        TextInput {
          id: input
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

          onEditingFinished: view.commit(row.modelData.key, text)
          Keys.onReturnPressed: view.commit(row.modelData.key, text)
          Keys.onEnterPressed: view.commit(row.modelData.key, text)

          Text {
            anchors.fill: parent
            visible: input.text === ""
            text: row.modelData.hint
            color: view.hud
            opacity: 0.25
            font: input.font
          }
        }
      }
    }
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

  // Read-only counters, so the two numbers the feed derives are visible
  // where the things that drive them are edited.
  Row {
    anchors {
      left: parent.left
      leftMargin: title.x
      bottom: parent.bottom
      bottomMargin: Math.round(14 * view.hudScale)
    }
    spacing: Math.round(24 * view.hudScale)

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
