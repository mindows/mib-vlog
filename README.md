# MIB Vlog

An Omarchy shell plugin: a red record dot on the status bar that opens a
Mars-mission style vlog panel — your front camera live in the background,
under a translucent mission-status HUD.

## What it does today

- **Bar widget** — a breathing red record dot, placeable in the `left`,
  `center`, or `right` section of the bar. Clicking it toggles the panel.
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
| MISSION DAY, SOL, HAB, BUNKS, LOG ENTRY > WATNEY, TIME, CONNECTED | editable labels, defaulting to the strings above |
| `WEATHER` | current conditions (SUNNY, RAIN, OVERCAST, ...) at the configured location, with a matching icon in the circle; refreshed on open and every 15 minutes |
| `SOL n` | whole days since the launch date, 0-based — launch day is sol 0 |
| `TIME hh:mm` | the current time, 24-hour |
| `CONNECTED:host addr` | this machine's hostname and the IPv4 address on its default route |
| `WATNEY #000` | the log entry counter, incremented per recording (recording is not built yet, so it stays at 0) |

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

## Not implemented yet

Recording. Nothing is written to disk and the microphone is never opened;
the `STANDBY` marker in the corner says as much. The oxygen and
temperature readouts are still static placeholder text.

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

## Layout

| File | What it is |
|---|---|
| `manifest.json` | plugin id, kinds (`bar-widget`, `overlay`), entry points |
| `BarWidget.qml` | the record dot; toggles the overlay |
| `Overlay.qml` | the camera card and the HUD |
| `SettingsStore.qml` | the settings file, the clock, sol, and the connection string |
| `SettingsView.qml` | the settings face of the card |
| `Weather.qml` | current conditions, the first-run location guess, and city search |
| `WeatherCodes.js` | WMO weather codes → HUD word and icon |
| `locate.sh` | Wi-Fi / IP location guess |
