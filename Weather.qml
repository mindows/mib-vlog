pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "Plugin.js" as Plugin
import "WeatherCodes.js" as WeatherCodes

// Current conditions at the configured location, plus the two lookups the
// settings face needs: a first-run guess of where this machine is, and a
// city search as the user types.
//
// Everything goes over curl to keyless services, the way Omarchy's own
// weather widget does it: Open-Meteo for conditions and city search, and
// locate.sh (BeaconDB, ipinfo.io, Nominatim) for the first guess. Each
// request runs through fetch.sh, which caps how much of an answer is read.
Item {
  id: weather

  required property var store
  // Only poll while the panel is on screen.
  property bool live: false

  // "Sunny", "Rain", ... and its glyph; empty until the first answer lands.
  property string label: ""
  property string glyph: ""
  // What to show instead of a condition: "Locating", "No signal", ...
  property string status: ""
  // Current air temperature in °C, NaN until the first answer. Always
  // fetched in Celsius so switching the display unit needs no refetch.
  property real temperatureC: NaN
  // US AQI (0-500), NaN until the first answer.
  property real aqi: NaN

  property var suggestions: []
  property bool searching: false

  readonly property bool hasLocation: store.locationName !== ""
  readonly property string pluginDir: Plugin.dir()

  // ------------------------------------------------------------ conditions

  function refresh() {
    if (!weather.hasLocation) return
    weather.refreshAirQuality()
    if (conditions.running) { weather.refreshQueued = true; return }
    conditions.command = ["bash", weather.pluginDir + "/fetch.sh", "8",
      "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + weather.store.latitude
      + "&longitude=" + weather.store.longitude
      + "&current=weather_code,is_day,temperature_2m"]
    conditions.running = true
  }

  property bool refreshQueued: false

  // Air quality is a separate Open-Meteo service, polled alongside the
  // conditions. A failed poll keeps the last reading.
  function refreshAirQuality() {
    if (airQuality.running) return
    airQuality.command = ["bash", weather.pluginDir + "/fetch.sh", "8",
      "https://air-quality-api.open-meteo.com/v1/air-quality"
      + "?latitude=" + weather.store.latitude
      + "&longitude=" + weather.store.longitude
      + "&current=us_aqi"]
    airQuality.running = true
  }

  Process {
    id: airQuality
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var current = null
        try {
          current = JSON.parse(text).current
        } catch (e) {
          current = null
        }
        if (current && current.us_aqi !== undefined && current.us_aqi !== null)
          weather.aqi = Number(current.us_aqi)
      }
    }
  }

  function applyConditions(text) {
    var current = null
    try {
      current = JSON.parse(text).current
    } catch (e) {
      current = null
    }
    if (!current || current.weather_code === undefined) {
      // Keep the last good reading on a failed poll; only a first failure
      // has nothing better to show.
      if (!weather.label) weather.status = "No signal"
      return
    }
    var described = WeatherCodes.describe(current.weather_code, current.is_day)
    weather.label = described.label
    weather.glyph = described.glyph
    weather.temperatureC = current.temperature_2m === undefined || current.temperature_2m === null
      ? NaN : Number(current.temperature_2m)
    weather.status = ""
  }

  Process {
    id: conditions
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: weather.applyConditions(text)
    }
    onExited: function(code) {
      if (code !== 0 && !weather.label) weather.status = "No signal"
      if (weather.refreshQueued) {
        weather.refreshQueued = false
        weather.refresh()
      }
    }
  }

  // Conditions change slowly and Open-Meteo updates every 15 minutes.
  Timer {
    running: weather.live && weather.hasLocation
    interval: 15 * 60 * 1000
    repeat: true
    onTriggered: weather.refresh()
  }

  onLiveChanged: if (live) refresh()

  // A new location means the old conditions belong to somewhere else.
  Connections {
    target: weather.store
    function onLatitudeChanged() { weather.relocated() }
    function onLongitudeChanged() { weather.relocated() }
    function onReadyChanged() { if (weather.store.ready && !weather.hasLocation) weather.locate() }
  }

  // Latitude and longitude land as two notifications; callLater folds them
  // into one refetch.
  function relocated() {
    Qt.callLater(weather.refetch)
  }

  function refetch() {
    weather.label = ""
    weather.glyph = ""
    weather.temperatureC = NaN
    weather.aqi = NaN
    weather.refresh()
  }

  Component.onCompleted: if (store.ready && !hasLocation) locate()

  // ---------------------------------------------------------- first guess

  function locate() {
    if (locator.running) return
    weather.status = "Locating"
    locator.command = ["bash", weather.pluginDir + "/locate.sh"]
    locator.running = true
  }

  Process {
    id: locator
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fix = null
        try {
          fix = JSON.parse(text)
        } catch (e) {
          fix = null
        }
        if (fix && fix.name && isFinite(fix.latitude) && isFinite(fix.longitude))
          weather.store.setLocation(fix.name, fix.latitude, fix.longitude)
      }
    }
    onExited: function(code) {
      if (!weather.hasLocation) weather.status = "No location"
    }
  }

  // ----------------------------------------------------------- city search

  // Debounced: one request per pause in typing, and a query that moved on
  // while a request was in flight runs once that request lands.
  property string pendingQuery: ""
  property string activeQuery: ""

  function search(query) {
    weather.pendingQuery = String(query || "").trim()
    if (weather.pendingQuery.length < 2) {
      searchDelay.stop()
      weather.suggestions = []
      weather.searching = false
      return
    }
    weather.searching = true
    searchDelay.restart()
  }

  function clearSearch() {
    searchDelay.stop()
    weather.pendingQuery = ""
    weather.suggestions = []
    weather.searching = false
  }

  Timer {
    id: searchDelay
    interval: 250
    onTriggered: weather.runSearch()
  }

  function runSearch() {
    if (geocoder.running || !weather.pendingQuery) return
    weather.activeQuery = weather.pendingQuery
    geocoder.command = ["bash", weather.pluginDir + "/fetch.sh", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name="
      + encodeURIComponent(weather.activeQuery) + "&count=6&language=en&format=json"]
    geocoder.running = true
  }

  Process {
    id: geocoder
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A stale answer for a query the user has already typed past is
        // dropped; the newer query is about to run.
        if (weather.activeQuery !== weather.pendingQuery) return
        var results = []
        try {
          results = JSON.parse(text).results || []
        } catch (e) {
          results = []
        }
        var out = []
        for (var i = 0; i < results.length; i++) {
          var r = results[i]
          if (!r || !isFinite(r.latitude) || !isFinite(r.longitude)) continue
          var parts = [r.name, r.admin1, r.country].filter(function(p) { return !!p })
          // "Santa Clara, Santa Clara" when admin1 repeats the city name.
          var name = Plugin.placeName(parts.filter(function(p, j) { return parts.indexOf(p) === j }).join(", "))
          if (name) out.push({ name: name, latitude: Number(r.latitude), longitude: Number(r.longitude) })
        }
        weather.suggestions = out
        weather.searching = false
      }
    }
    onExited: function(code) {
      if (code !== 0 && weather.activeQuery === weather.pendingQuery) {
        weather.suggestions = []
        weather.searching = false
      }
      if (weather.pendingQuery && weather.pendingQuery !== weather.activeQuery) weather.runSearch()
    }
  }
}
