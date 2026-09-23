.pragma library

// WMO weather interpretation codes, as Open-Meteo reports them, mapped to a
// short HUD word and a Nerd Font weather glyph. The glyphs are the same
// nf-weather set Omarchy's own weather widget draws.

var SUN = ""
var MOON = ""
var PARTLY_DAY = ""
var PARTLY_NIGHT = ""
var CLOUD = ""
var FOG_DAY = ""
var FOG_NIGHT = ""
var DRIZZLE_DAY = ""
var DRIZZLE_NIGHT = ""
var RAIN = ""
var SLEET = ""
var SNOW = ""
var STORM = ""

// Words stay short: the value line shares the stack with the other readouts.
function describe(code, isDay) {
  var c = parseInt(String(code), 10)
  var day = Number(isDay) !== 0
  if (isNaN(c)) return { label: "", glyph: "" }
  if (c === 0) return day ? { label: "Sunny", glyph: SUN } : { label: "Clear", glyph: MOON }
  if (c === 1 || c === 2) return { label: "Partly cloudy", glyph: day ? PARTLY_DAY : PARTLY_NIGHT }
  if (c === 3) return { label: "Overcast", glyph: CLOUD }
  if (c === 45 || c === 48) return { label: "Fog", glyph: day ? FOG_DAY : FOG_NIGHT }
  if (c >= 51 && c <= 55) return { label: "Drizzle", glyph: day ? DRIZZLE_DAY : DRIZZLE_NIGHT }
  if (c === 56 || c === 57 || c === 66 || c === 67) return { label: "Freezing rain", glyph: SLEET }
  if (c === 61 || c === 63) return { label: "Rain", glyph: RAIN }
  if (c === 65) return { label: "Heavy rain", glyph: RAIN }
  if (c >= 71 && c <= 77) return { label: "Snow", glyph: SNOW }
  if (c >= 80 && c <= 82) return { label: "Showers", glyph: RAIN }
  if (c === 85 || c === 86) return { label: "Snow showers", glyph: SNOW }
  if (c >= 95) return { label: "Storm", glyph: STORM }
  return { label: "Cloudy", glyph: CLOUD }
}
