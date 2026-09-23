pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Everything the HUD reads that is not the camera: the editable labels, the
// mission clock, the sol counter, and the connection string.
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
  readonly property string connectedLabel: data.connectedLabel
  readonly property string launchDate: data.launchDate
  readonly property int entryCount: data.entryCount

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
  property string connection: ""

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
    // Only once the directory exists can a first write land, and only then
    // is a missing launch date worth defaulting: the first run is launch day.
    onExited: function(code) {
      if (code !== 0) return
      if (!store.launchDate) store.setLaunchDate(store.todayText())
    }
  }

  FileView {
    id: file
    path: store.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()

    JsonAdapter {
      id: data
      property string missionLabel: "MISSION DAY"
      property string solLabel: "SOL"
      property string habLabel: "HAB"
      property string locationLabel: "BUNKS"
      property string logLabel: "LOG ENTRY > WATNEY"
      property string timeLabel: "TIME"
      property string connectedLabel: "CONNECTED"
      property string launchDate: ""
      property int entryCount: 0
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

  // Hostname plus the address on the route that actually reaches the world,
  // which is the one worth showing on a mission feed.
  Process {
    id: netProbe
    command: ["sh", "-c",
      "printf '%s %s' \"$(hostname)\" \"$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ print $7; exit }')\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.connection = text.trim()
    }
  }

  onLiveChanged: if (live) netProbe.running = true
}
