#!/usr/bin/env bash
# Best-effort guess of where this machine is, for the weather readout.
#
# Prints one JSON object — {"name", "latitude", "longitude", "source"} — or
# nothing and exits non-zero when every source fails.
#
#   1. Nearby Wi-Fi access points (BSSIDs + signal only, never SSIDs) go to
#      BeaconDB, the community successor to Mozilla Location Service. It falls
#      back to IP geolocation itself when it does not know the networks.
#      Networks whose SSID ends in "_nomap" have opted out and are skipped.
#   2. If that fails, ipinfo.io's IP lookup.
#
# Coordinates are then named via OpenStreetMap's Nominatim, as
# "City, State, Country".

set -uo pipefail

UA="mib-vlog/0.1 (omarchy plugin)"

access_points() {
  command -v nmcli >/dev/null || return 0
  # "auto" rescans when the cached list is stale; a pruned cache can hold
  # nothing but the connected access point.
  nmcli -t -e yes -f SSID,BSSID,SIGNAL dev wifi list --rescan auto 2>/dev/null |
    jq -R -s -c '
      split("\n") | map(select(length > 0))
      | map(
          # nmcli escapes ":" inside fields as "\:"; split on the bare ones.
          [splits("(?<!\\\\):")] | map(gsub("\\\\:"; ":"))
          | select(length >= 3)
          | select(.[0] | endswith("_nomap") | not)
          | {macAddress: (.[1] | ascii_downcase),
             signalStrength: ((.[2] | tonumber? // 0) / 2 - 100 | floor)})
      | .[:40]'
}

from_beacondb() {
  local aps
  aps=$(access_points)
  [[ -n $aps ]] || aps="[]"
  curl -fsS --max-time 8 -A "$UA" -H 'Content-Type: application/json' \
    -d "{\"considerIp\":true,\"wifiAccessPoints\":$aps}" \
    https://api.beacondb.net/v1/geolocate 2>/dev/null |
    jq -ec '{latitude: .location.lat, longitude: .location.lng,
             source: (if .fallback then "ip" else "wifi" end)}' 2>/dev/null
}

from_ipinfo() {
  curl -fsS --max-time 6 -A "$UA" https://ipinfo.io/json 2>/dev/null |
    jq -ec '(.loc | split(",")) as $ll
            | {latitude: ($ll[0] | tonumber), longitude: ($ll[1] | tonumber),
               name: ([.city, .region, .country] | map(select(. != null and . != "")) | join(", ")),
               source: "ip"}' 2>/dev/null
}

place_name() {
  curl -fsS --max-time 6 -A "$UA" \
    "https://nominatim.openstreetmap.org/reverse?lat=$1&lon=$2&format=jsonv2&zoom=10&accept-language=en" 2>/dev/null |
    jq -er '.address
            | [(.city // .town // .village // .hamlet // .county), .state, .country]
            | map(select(. != null and . != "")) | join(", ")
            | select(length > 0)' 2>/dev/null
}

fix=$(from_beacondb) || fix=$(from_ipinfo) || exit 1

lat=$(jq -r .latitude <<<"$fix")
lon=$(jq -r .longitude <<<"$fix")
name=$(place_name "$lat" "$lon") || name=$(jq -r '.name // empty' <<<"$fix")
[[ -n $name ]] || name=$(printf '%.3f, %.3f' "$lat" "$lon")

jq -cn --arg name "$name" --argjson fix "$fix" '$fix + {name: $name}'
