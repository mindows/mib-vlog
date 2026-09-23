import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar half of MIB Vlog: a red record dot that toggles the vlog overlay.
//
// The overlay lives in the same plugin, so the shell facade handed to this
// widget already owns the target; `bar.run` is only a fallback for hosts that
// do not inject one.
BarWidget {
  id: root
  moduleName: "mib-vlog"

  readonly property color recordColor: "#e8413a"

  // Mirrors the panel's record marker: faded at standby, a slow blink while
  // a take is running. The panel is a separate component instance, so it
  // publishes its state to a file in the runtime dir and this watches it.
  readonly property bool recording: stateFile.loaded && stateFile.text().trim() === "recording"
  property real blink: 1.0

  SequentialAnimation on blink {
    running: root.recording
    loops: Animation.Infinite
    NumberAnimation { to: 0.15; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
  }

  FileView {
    id: stateFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/mib-vlog.state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    // The panel writes the file once it loads; until then, keep looking.
    onLoadFailed: retry.start()
  }

  Timer {
    id: retry
    interval: 2000
    onTriggered: stateFile.reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleOverlay() {
    var shell = bar ? bar.shell : null
    if (shell && typeof shell.toggle === "function") {
      if (shell.toggle(root.moduleName, "{}") !== false) return
    }
    if (bar && typeof bar.run === "function")
      bar.run("omarchy-shell shell toggle " + root.moduleName)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.recording ? "Vlog — recording" : "Vlog"
    onPressed: function(b) { root.toggleOverlay() }

    // A record button: a foreground-coloured ring, a small gap, then the
    // red dot. The ring takes the bar's foreground so it sits with the
    // neighbouring icons; the dot stays record-red in every theme.
    iconComponent: Component {
      Item {
        id: icon
        readonly property real ringSize: Math.round(Math.min(width, height) * 0.9)
        readonly property real ringStroke: Math.max(1, Math.round(ringSize * 0.09))
        readonly property real gap: Math.max(2, Math.round(ringSize * 0.14))

        Rectangle {
          anchors.centerIn: parent
          width: icon.ringSize
          height: width
          radius: width / 2
          color: "transparent"
          border.width: icon.ringStroke
          border.color: root.bar && root.bar.foreground ? root.bar.foreground : "white"
        }

        Rectangle {
          anchors.centerIn: parent
          width: icon.ringSize - 2 * (icon.ringStroke + icon.gap)
          height: width
          radius: width / 2
          color: root.recordColor
          opacity: root.recording ? root.blink : 0.4
        }
      }
    }
  }
}
