pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// One take at a time, from the panel's camera and the default microphone.
//
// A take is written to a hidden file beside its final name, and only once
// the recorder has closed it cleanly does finalize.sh turn it into
// YYYYMMDD-<sol>-<seq>.mp4 — so a half-written take never sits under a real
// name. The seq is the log index on the feed; it advances per saved take.
Item {
  id: recording

  required property var store

  // idle -> preparing -> recording -> stopping -> idle. (Not `state`:
  // Item already has one, for its States.)
  property string phase: "idle"
  property string error: ""

  readonly property bool active: phase === "preparing" || phase === "recording"
  // True until the recorder has let go of the file; the camera has to stay
  // on that long or the end of the take is lost.
  readonly property bool busy: phase !== "idle"

  // Handed to the panel's CaptureSession.
  property alias recorder: rec
  property alias microphone: mic

  property string finalPath: ""
  property string partialPath: ""
  property bool stopRequested: false

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }

  function toggle() {
    if (recording.active) recording.stop()
    else if (!recording.busy) recording.start()
  }

  function start() {
    if (recording.busy) return
    recording.error = ""
    recording.stopRequested = false
    recording.phase = "preparing"
    var seq = String(recording.store.entryCount)
    while (seq.length < 3) seq = "0" + seq
    var base = Qt.formatDateTime(new Date(), "yyyyMMdd") + "-" + recording.store.sol + "-" + seq
    prepare.command = ["bash", recording.pluginDir + "/prepare.sh", recording.store.outputPath, base]
    prepare.running = true
  }

  function stop() {
    if (recording.phase === "preparing") {
      // The file names are still being reserved; stop as soon as they are.
      recording.stopRequested = true
    } else if (recording.phase === "recording") {
      recording.phase = "stopping"
      rec.stop()
    }
  }

  function fail(message) {
    recording.error = message
    recording.phase = "idle"
  }

  Process {
    id: prepare
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var paths = text.trim().split("\t")
        if (paths.length !== 2 || !paths[0] || !paths[1]) {
          recording.fail("Cannot write to " + recording.store.outputDir)
          return
        }
        if (recording.stopRequested) {
          recording.phase = "idle"
          return
        }
        recording.finalPath = paths[0]
        recording.partialPath = paths[1]
        rec.outputLocation = "file://" + encodeURI(paths[1])
        rec.record()
      }
    }
    onExited: function(code) {
      if (code !== 0 && recording.phase === "preparing")
        recording.fail("Cannot write to " + recording.store.outputDir)
    }
  }

  AudioInput { id: mic }

  MediaRecorder {
    id: rec
    mediaFormat {
      fileFormat: MediaFormat.MPEG4
      videoCodec: MediaFormat.VideoCodec.H264
      audioCodec: MediaFormat.AudioCodec.AAC
    }
    quality: MediaRecorder.HighQuality

    onRecorderStateChanged: {
      if (rec.recorderState === MediaRecorder.RecordingState) {
        recording.phase = "recording"
      } else if (rec.recorderState === MediaRecorder.StoppedState && recording.phase !== "idle") {
        var saved = recording.phase === "stopping" && !recording.error
        recording.phase = "idle"
        if (!saved) return
        // The take is on disk: the next one gets the next index, whatever
        // happens to the re-encode.
        recording.store.countEntry()
        Quickshell.execDetached(["bash", recording.pluginDir + "/finalize.sh",
          recording.partialPath, recording.finalPath])
      }
    }

    onErrorOccurred: function(error, errorString) {
      recording.error = errorString || "Recording failed"
      if (rec.recorderState === MediaRecorder.StoppedState) recording.phase = "idle"
    }
  }
}
