.pragma library

// Things every part of the plugin shares.

// The record marker's red: the bar dot and the HUD's record marker.
var recordColor = "#e8413a"

// Place names come from outside services (Nominatim, ipinfo.io, Open-Meteo's
// city search), so they are cleaned before they are kept or shown: control
// and invisible formatting characters (including the bidi overrides that can
// make a name read as something else) become spaces, runs of space collapse,
// and the result is cut to placeNameLimit characters.
var placeNameLimit = 120

function placeName(value) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
  var chars = Array.from(text)
  return chars.length > placeNameLimit ? chars.slice(0, placeNameLimit).join("").trim() : text
}

// The plugin's own folder on disk, for running the scripts that ship with it.
// This file sits in that folder, so it resolves against itself.
function dir() {
  var url = String(Qt.resolvedUrl("."))
  return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
}
