# MIB Vlog

An Omarchy shell plugin: a red record dot on the status bar that opens a
Mars-mission style vlog panel — your front camera live in the background,
under a translucent mission-status HUD.

## What it does today

- **Bar widget** — a record button (red dot inside a ring), placeable in the
  `left`, `center`, or `right` section of the bar. Clicking it toggles the
  panel. The dot is faded at standby and blinks slowly while recording.
- **Overlay** — a 500x250 card at the top center of the screen. The front camera
  fills the card; the HUD (MISSION DAY / SOL, the pressure, oxygen, and
  temperature stack, LOG ENTRY, HAB > BUNKS) is drawn over it.
- **Click anywhere on the panel to close it.** `Esc` and `q` close it too.
- **Settings** — the gear beside STANDBY swaps the card over to its own
  settings face. `Esc` or the gear again returns to the feed.

The camera is only active while the panel is open, so closing it releases
`/dev/video*` and drops the webcam light.

## What the HUD shows

| Reading | Where it comes from |
|---|---|
| MISSION DAY, SOL, HAB, BUNKS, LOG ENTRY > WATNEY, TIME | editable labels, defaulting to the strings above |
| `WEATHER` | current conditions (SUNNY, RAIN, OVERCAST, ...) at the configured location, with a matching icon in the circle; refreshed on open and every 15 minutes |
| `TEMP` | current air temperature in °C or °F (a settings choice, °C by default), with the scale letter in the circle and its outline lit clockwise as a gauge: -10..50 °C, 0..130 °F. Updates with each weather fetch |
| `AQI` | current US air quality index (0-500) from Open-Meteo, with a thumbs-up at 100 or under (good/moderate) and thumbs-down above; the circle is a 0-500 gauge. Updates with each weather fetch |
| `SOL n` | whole days since the launch date, 0-based — launch day is sol 0 |
| `TIME hh:mm` | the current time, 24-hour |
| `host \| location` | this machine's hostname and the weather location |
| `WATNEY #000` | the log index: takes saved so far this sol, starting over at 000 each new sol |

### Location

The first open guesses where you are: nearby Wi-Fi access points (BSSIDs and
signal strength only — never network names, and networks named `*_nomap` are
skipped) go to [BeaconDB](https://beacondb.net), which falls back to IP
geolocation; if that fails, ipinfo.io's IP lookup. The coordinates are named
via OpenStreetMap's Nominatim. See `locate.sh`.

The settings face's LOCATION box is a search: type part of a city and pick a
match (arrow keys + Enter, or click). Empty the box and press Enter to guess
again. Weather and city search come from [Open-Meteo](https://open-meteo.com),
which needs no API key.

Settings live in `~/.config/mib-vlog/settings.json`, which is written on the
first open — the launch date defaults to that day, so a fresh install starts
at sol 0. Editing the file by hand works too; the panel reloads on change.

To open straight onto the settings face:

```bash
omarchy-shell shell summon mib-vlog '{"settings":true}'
```

## Recording

Click **STANDBY** (or its dot) to start a take: the label becomes
**RECORDING** and the dot blinks. Click again to stop — or just close the
panel, which stops and saves the take too.

Takes are saved to the output folder (default `~/mib-vlogs`, created on
demand; change it in settings) as `YYYYMMDD-<sol>-<seq>.mp4`, e.g.
`20260922-0-000.mp4`, where `<seq>` is the log index on the feed. If the name
is taken, `-1`, `-2`, ... is appended.

- Video is the camera at 1280x720; sound is the system's default microphone
  as of the moment the take starts, so switching mics takes effect on the
  next take. The HUD is not burned into the file, and the image is not
  mirrored (the preview is).
- Picture and sound are recorded separately — Qt for video, PipeWire's
  `pw-record` for audio — because inside the long-running shell Qt keeps
  recording whichever mic was the default when the panel first loaded. They
  are stopped together and lined up by their ends.
- A take is written to hidden `.<name>.recording.mp4` / `.wav` files and
  becomes the real file only once both have closed. `finalize.sh` then joins
  them and re-encodes to 8-bit 4:2:0 H.264 with `ffmpeg`, because Qt's
  recorder writes 10-bit 4:4:4, which browsers, phones, and QuickTime cannot
  play. A notification says when the file is saved.
- The microphone is opened only during a take.

### If the sound is distorted

Check the microphone's input gain before anything else. A capture chain
turned all the way up clips ordinary room sound into harsh, buzzing noise
that no player or encoder can undo. For a built-in laptop mic, e.g.:

```bash
amixer -c 0 sget 'Internal Mic Boost'   # 3 = +30 dB, often far too hot
amixer -c 0 sset 'Internal Mic Boost' 0
```

Start or stop a take from a script or keybinding while the panel is open:

```bash
omarchy-shell shell call mib-vlog toggleRecording ""
```

## Install

```bash
git clone <this repo> ~/.config/omarchy/plugins/mib-vlog
omarchy-shell shell rescanPlugins
omarchy plugin enable mib-vlog
```

The widget lands in the bar's right section. Move it with:

```bash
omarchy bar move mib-vlog --section left     # or center, right
```

Toggle the panel without the bar:

```bash
omarchy-shell shell toggle mib-vlog
```

Disable or remove it with `omarchy plugin disable mib-vlog` /
`omarchy plugin remove mib-vlog`.

## Requirements

- Omarchy shell (Quickshell) with plugin schema version 1
- `qt6-multimedia` and a camera at `/dev/video*`
- `curl` and `jq`; `nmcli` for the Wi-Fi part of the location guess
- `ffmpeg` to join and re-encode takes (without it the picture is kept as
  recorded, without sound)
- `pw-record` and `pactl` (PipeWire) for the sound

## Layout

| File | What it is |
|---|---|
| `manifest.json` | plugin id, kinds (`bar-widget`, `overlay`), entry points |
| `BarWidget.qml` | the record dot; toggles the overlay |
| `Overlay.qml` | the camera card and the HUD |
| `SettingsStore.qml` | the settings file, the clock, sol, and the hostname |
| `SettingsView.qml` | the settings face of the card |
| `Weather.qml` | current conditions, the first-run location guess, and city search |
| `WeatherCodes.js` | WMO weather codes → HUD word and icon |
| `locate.sh` | Wi-Fi / IP location guess |
| `Recording.qml` | takes: start/stop, file naming, hand-off to finalize |
| `prepare.sh` | creates the output folder and picks a free file name |
| `finalize.sh` | joins a take's picture and sound, re-encodes, and moves it to its final name |
