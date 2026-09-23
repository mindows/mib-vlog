.pragma library

// Things every part of the plugin shares.

// The record marker's red: the bar dot and the HUD's record marker.
var recordColor = "#e8413a"

// The plugin's own folder on disk, for running the scripts that ship with it.
// This file sits in that folder, so it resolves against itself.
function dir() {
  var url = String(Qt.resolvedUrl("."))
  return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
}
