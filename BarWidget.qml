import QtQuick
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
    tooltipText: "Vlog"
    onPressed: function(b) { root.toggleOverlay() }

    // Drawn rather than glyphed: the dot has to stay record-red in every
    // theme, while a font icon would take the bar foreground.
    iconComponent: Component {
      Item {
        Rectangle {
          anchors.centerIn: parent
          width: Math.round(Math.min(parent.width, parent.height) * 0.62)
          height: width
          radius: width / 2
          color: root.recordColor

          // A slow breath, so the dot reads as "ready to record" instead of
          // as a static status light.
          SequentialAnimation on opacity {
            running: true
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.55; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
          }
        }
      }
    }
  }
}
