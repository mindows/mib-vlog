pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// One take at a time, from the panel's camera and the system's current
// default microphone.
//
// Video and sound are recorded separately and joined afterwards. Qt records
// the picture; PipeWire's pw-record records the sound. Qt could record both,
// but inside the long-running shell it keeps capturing from whichever mic was
// the default when the panel first loaded — switching mics later, or handing
// it a different device, is ignored. pw-record starts fresh for every take,
// aimed at the mic prepare.sh reports as the default right then.
//
// Both halves are written to hidden files beside the take's final name, and
// only once both have closed does finalize.sh join them into
// YYYYMMDD-<sol>-<seq>.mp4 — so a half-written take never sits under a real
// name. The seq is the log index on the feed; it advances per saved take.
//
// The HUD is burned in at save time from snapshots of an off-screen copy of
// it (hudSource): one as the take starts, and one per minute after, each
// tagged with its offset into the take so the clock in the video turns over
// exactly on the minute.
Item {
  id: recording

  required property var store
  // Conditions at the start of a take, for the file's metadata.
  property var weather: null
  // The item snapshotted for the burned-in HUD.
  property var hudSource: null

  // idle -> preparing -> recording -> stopping -> idle. (Not `state`:
  // Item already has one, for its States.)
  property string phase: "idle"
  property string error: ""

  readonly property bool active: phase === "preparing" || phase === "recording"
  // True until both halves have let go of their files; the camera has to
  // stay on that long or the end of the take is lost.
  readonly property bool busy: phase !== "idle"

  // Handed to the panel's CaptureSession, which records video only.
  property alias recorder: rec

  property string finalPath: ""
  property string partialPath: ""
  readonly property string audioPath: partialPath.replace(/\.mp4$/, ".wav")
  property bool stopRequested: false
  property bool videoClosed: false
  property bool audioClosed: false

  property string hudDir: ""
  property real startedAt: 0
  // Seconds into the take at which each snapshot takes over, in file order.
  property var hudOffsets: []
  // What the take is, as metadata for its file; captured when it starts.
  property var takeInfo: ({})

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
    recording.partialPath = ""
    recording.hudDir = ""
    recording.hudOffsets = []
    recording.videoClosed = false
    recording.audioClosed = false
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
      // Stopped together, so the two halves end at the same moment; that is
      // what finalize.sh lines them up on.
      rec.stop()
      recording.stopMicrophone()
    }
  }

  function stopMicrophone() {
    if (microphone.running) {
      // SIGINT: pw-record finishes the WAV header before it exits.
      microphone.signal(2)
      micDeadline.start()
    } else {
      recording.audioClosed = true
    }
  }

  function fail(message) {
    recording.error = message
    recording.phase = "idle"
  }

  // The video half has closed — on request, or on its own after an error,
  // in which case the microphone is taken down with it.
  function videoStopped() {
    if (recording.videoClosed || !recording.partialPath || recording.phase === "idle") return
    if (recording.phase !== "stopping") {
      recording.phase = "stopping"
      recording.stopMicrophone()
    }
    recording.videoClosed = true
    recording.settle()
  }

  // Both halves are closed: hand the take off, or drop it if it failed.
  function settle() {
    if (!recording.videoClosed || !recording.audioClosed || recording.phase === "idle") return
    micDeadline.stop()
    var saved = !recording.error
    recording.phase = "idle"
    if (!saved) {
      Quickshell.execDetached(["rm", "-rf", recording.partialPath, recording.audioPath,
        recording.hudDir])
      return
    }
    // The take is on disk: the next one gets the next index, whatever
    // happens to the re-encode.
    recording.store.countEntry()
    Quickshell.execDetached(["bash", recording.pluginDir + "/finalize.sh",
      recording.partialPath, recording.audioPath, recording.finalPath,
      recording.store.noiseReduction ? "denoise" : "",
      recording.hudDir, recording.hudOffsets.join(","),
      recording.store.mirrorVideo ? "mirror" : "",
      JSON.stringify(recording.takeInfo),
      recording.store.transcribe ? "transcribe" : ""])
  }

  // ISO 8601 in local time with its UTC offset, e.g. 2026-09-22T21:16:50-07:00.
  function localIso(date) {
    function pad(n) { return (n < 10 ? "0" : "") + n }
    var offset = -date.getTimezoneOffset()
    var sign = offset >= 0 ? "+" : "-"
    offset = Math.abs(offset)
    return Qt.formatDateTime(date, "yyyy-MM-ddTHH:mm:ss")
      + sign + pad(Math.floor(offset / 60)) + ":" + pad(offset % 60)
  }

  // The take's metadata, as it stands at the start: where, on what, in what
  // weather, and when. finalize.sh adds the duration.
  function describeTake() {
    var store = recording.store
    var weather = recording.weather
    var start = new Date(recording.startedAt)
    var seq = String(store.entryCount)
    while (seq.length < 3) seq = "0" + seq

    var temperature = ""
    if (weather && !isNaN(weather.temperatureC)) {
      var value = store.tempUnit === "F" ? weather.temperatureC * 9 / 5 + 32 : weather.temperatureC
      temperature = value.toFixed(1) + " °" + store.tempUnit
    }
    var aqi = weather && !isNaN(weather.aqi) ? String(Math.round(weather.aqi)) : ""
    var conditions = weather ? weather.label : ""
    var hasPlace = store.locationName !== ""

    return {
      title: store.logLabel + " #" + seq,
      startUtc: start.toISOString(),
      startLocal: recording.localIso(start),
      location: store.locationName,
      latitude: hasPlace ? store.latitude : null,
      longitude: hasPlace ? store.longitude : null,
      hostname: store.hostname,
      weather: conditions,
      temperature: temperature,
      aqi: aqi,
      sol: String(store.sol),
      logEntry: seq
    }
  }

  // Saves the HUD as it looks now, to take over at `offset` seconds.
  function snapshot(offset) {
    if (!recording.hudSource || !recording.hudDir) return
    var name = String(recording.hudOffsets.length)
    while (name.length < 3) name = "0" + name
    var path = recording.hudDir + "/" + name + ".png"
    var offsets = recording.hudOffsets.slice()
    offsets.push(Math.max(0, offset).toFixed(3))
    recording.hudOffsets = offsets
    // A snapshot that fails leaves its file missing; finalize.sh skips it
    // and the one before simply runs longer.
    recording.hudSource.grabToImage(function(result) { result.saveToFile(path) })
  }

  // The clock turned over: snapshot the new minute, placed at the minute's
  // true start rather than at the timer tick that noticed it.
  Connections {
    target: recording.store
    function onClockChanged() {
      if (recording.phase !== "recording") return
      var minute = new Date()
      minute.setSeconds(0, 0)
      var offset = (minute.getTime() - recording.startedAt) / 1000
      var last = recording.hudOffsets.length
        ? Number(recording.hudOffsets[recording.hudOffsets.length - 1]) : -1
      if (offset > last) recording.snapshot(offset)
    }
  }

  Process {
    id: prepare
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fields = text.replace(/\n$/, "").split("\t")
        if (fields.length < 2 || !fields[0] || !fields[1]) {
          recording.fail("Cannot write to " + recording.store.outputDir)
          return
        }
        if (recording.stopRequested) {
          recording.phase = "idle"
          return
        }
        recording.finalPath = fields[0]
        recording.partialPath = fields[1]
        recording.hudDir = fields[3] || ""
        var command = ["pw-record", "--rate", "48000", "--channels", "2", "--format", "s16"]
        if (fields[2]) command.push("--target", fields[2])
        command.push(recording.audioPath)
        microphone.command = command
        microphone.running = true
        rec.outputLocation = "file://" + encodeURI(fields[1])
        rec.record()
      }
    }
    onExited: function(code) {
      if (code !== 0 && recording.phase === "preparing")
        recording.fail("Cannot write to " + recording.store.outputDir)
    }
  }

  // The sound half of a take.
  Process {
    id: microphone
    onExited: {
      recording.audioClosed = true
      recording.settle()
    }
  }

  // pw-record exits at once on SIGINT; if it ever hangs, the take is still
  // saved, just without sound.
  Timer {
    id: micDeadline
    interval: 3000
    onTriggered: {
      if (microphone.running) microphone.running = false
      recording.audioClosed = true
      recording.settle()
    }
  }

  MediaRecorder {
    id: rec
    mediaFormat {
      fileFormat: MediaFormat.MPEG4
      videoCodec: MediaFormat.VideoCodec.H264
    }
    quality: MediaRecorder.HighQuality

    onRecorderStateChanged: {
      if (rec.recorderState === MediaRecorder.RecordingState) {
        recording.phase = "recording"
        recording.startedAt = Date.now()
        recording.takeInfo = recording.describeTake()
        recording.snapshot(0)
      }
      else if (rec.recorderState === MediaRecorder.StoppedState) recording.videoStopped()
    }

    onErrorOccurred: function(error, errorString) {
      recording.error = errorString || "Recording failed"
      if (rec.recorderState === MediaRecorder.StoppedState) {
        if (recording.partialPath) recording.videoStopped()
        else recording.phase = "idle"
      }
    }
  }
}
