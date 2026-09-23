pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Everything the HUD reads that is not the camera: the editable labels, the
// mission clock, the sol counter, and this machine's hostname.
//
// Labels and the launch date persist to ~/.config/mib-vlog/settings.json.
// The file is the whole state; there is no shell.json coupling, because the
// shell hands a bar widget its inline settings but hands a summoned overlay
// nothing to read them from.
Item {
  id: store

  // Live values are only worth computing while the panel is on screen.
  property bool live: false

  readonly property string configDir: Quickshell.env("HOME") + "/.config/mib-vlog"
  readonly property string configPath: configDir + "/settings.json"

  // ------------------------------------------------------------- persisted

  readonly property string missionLabel: data.missionLabel
  readonly property string solLabel: data.solLabel
  readonly property string habLabel: data.habLabel
  readonly property string locationLabel: data.locationLabel
  readonly property string logLabel: data.logLabel
  readonly property string timeLabel: data.timeLabel
  readonly property string launchDate: data.launchDate
  readonly property int entryCount: data.entryCount

  // Where the weather is read for. An empty name means never set, and the
  // first open guesses it.
  readonly property string locationName: data.locationName
  readonly property real latitude: data.latitude
  readonly property real longitude: data.longitude

  // True once the settings file has been read (or found missing) and its
  // directory exists — the point at which defaults can be written without
  // clobbering a file that simply had not loaded yet.
  readonly property bool ready: store.fileResolved && store.dirReady
  property bool fileResolved: false
  property bool dirReady: false

  // ---------------------------------------------------------------- derived

  // Sol 0 is launch day, so today's sol is the whole-day count since then.
  // Both ends are taken at local midnight, which keeps a DST boundary from
  // rounding a day away.
  readonly property int sol: {
    var launch = store.parseDate(store.launchDate)
    if (!launch) return 0
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    return Math.max(0, Math.round((today.getTime() - launch.getTime()) / 86400000))
  }

  property string clock: Qt.formatDateTime(new Date(), "HH:mm")
  property string hostname: ""

  // The recording counter. Recording is not implemented yet; this is the
  // hook it will call once a take has been written.
  function countEntry() {
    data.entryCount = data.entryCount + 1
    store.save()
  }

  // ------------------------------------------------------------ mutations

  function setLabel(key, value) {
    var text = String(value)
    if (data[key] === text) return
    data[key] = text
    store.save()
  }

  // An unparseable date is left in the file as typed rather than silently
  // rewritten — the field shows what the user entered, and sol falls back to 0.
  function setLaunchDate(value) {
    var text = String(value).trim()
    if (data.launchDate === text) return
    data.launchDate = text
    store.save()
  }

  function setLocation(name, latitude, longitude) {
    data.locationName = String(name)
    data.latitude = Number(latitude)
    data.longitude = Number(longitude)
    store.save()
  }

  function save() {
    file.writeAdapter()
  }

  function parseDate(text) {
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text || "").trim())
    if (!match) return null
    var year = parseInt(match[1], 10)
    var month = parseInt(match[2], 10)
    var day = parseInt(match[3], 10)
    var date = new Date(year, month - 1, day)
    // Rejects 2026-02-31 and friends, which Date would roll forward.
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day)
      return null
    date.setHours(0, 0, 0, 0)
    return date
  }

  function todayText() {
    return Qt.formatDateTime(new Date(), "yyyy-MM-dd")
  }

  // ---------------------------------------------------------------- storage

  Component.onCompleted: mkdir.running = true

  Process {
    id: mkdir
    command: ["mkdir", "-p", store.configDir]
    onExited: function(code) { store.dirReady = code === 0 }
  }

  // The first run is launch day. Written only once `ready`: the file loads
  // asynchronously, and defaulting before it lands would overwrite a real
  // launch date with today's.
  onReadyChanged: if (ready && !launchDate) setLaunchDate(todayText())

  FileView {
    id: file
    path: store.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: store.fileResolved = true
    // A missing file is the first run, not an error: the defaults stand.
    onLoadFailed: store.fileResolved = true

    JsonAdapter {
      id: data
      property string missionLabel: "MISSION DAY"
      property string solLabel: "SOL"
      property string habLabel: "HAB"
      property string locationLabel: "BUNKS"
      property string logLabel: "LOG ENTRY > WATNEY"
      property string timeLabel: "TIME"
      property string launchDate: ""
      property int entryCount: 0
      property string locationName: ""
      property real latitude: 0
      property real longitude: 0
    }
  }

  // ------------------------------------------------------------- live data

  Timer {
    running: store.live
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: store.clock = Qt.formatDateTime(new Date(), "HH:mm")
  }

  // Read once: a hostname does not change under a running session.
  Process {
    running: true
    command: ["hostname"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.hostname = text.trim()
    }
  }
}
