# MIB Vlog

An Omarchy shell plugin: a red record dot on the status bar that opens a
Mars-mission style vlog panel — your front camera live in the background,
under a translucent mission-status HUD.

## What it does today

- **Bar widget** — a breathing red record dot, placeable in the `left`,
  `center`, or `right` section of the bar. Clicking it toggles the panel.
- **Overlay** — a 500x250 card at the top center of the screen. The front camera
  fills the card; the HUD (MISSION DAY / SOL 19, the pressure, oxygen, and
  temperature stack, LOG ENTRY, HAB > BUNKS) is drawn over it.
- **Click anywhere on the panel to close it.** `Esc` and `q` close it too.

The camera is only active while the panel is open, so closing it releases
`/dev/video*` and drops the webcam light.

## Not implemented yet

Recording. The HUD readouts are static placeholder text — nothing is
sampled, nothing is written to disk, and the microphone is never opened.
The `STANDBY` marker in the corner says as much.

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

## Layout

| File | What it is |
|---|---|
| `manifest.json` | plugin id, kinds (`bar-widget`, `overlay`), entry points |
| `BarWidget.qml` | the record dot; toggles the overlay |
| `Overlay.qml` | the camera card and the HUD |
