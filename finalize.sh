#!/usr/bin/env bash
# Turn a finished take into its final file.
#
#   finalize.sh <recording> <final>
#
# Qt's recorder writes H.264 in 10-bit 4:4:4, which mpv and VLC play but
# browsers, phones, and QuickTime do not. Re-encoding to 8-bit 4:2:0 makes
# the file play anywhere. If ffmpeg is missing or fails, the raw take is
# kept under the final name rather than lost.

set -uo pipefail

recording=$1
final=$2

if command -v ffmpeg >/dev/null &&
  ffmpeg -n -loglevel error -i "$recording" \
    -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    -c:a aac -b:a 160k -movflags +faststart "$final"; then
  rm -f "$recording"
else
  rm -f "$final"
  mv -n "$recording" "$final"
fi

[[ -e $final ]] || exit 1

if command -v notify-send >/dev/null; then
  notify-send -a "MIB Vlog" "Log entry saved" "$(basename "$final")"
fi
