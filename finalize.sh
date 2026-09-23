#!/usr/bin/env bash
# Join a finished take's two halves into its final file.
#
#   finalize.sh <video> <audio> <final> [denoise]
#
# <video> is Qt's recording (picture only) and <audio> is pw-record's WAV.
# They were started a moment apart but stopped together, so they are lined
# up by their ends: when the audio is longer its head is trimmed, and when
# it is shorter it is delayed, by the difference.
#
# The video is re-encoded too: Qt's recorder writes H.264 in 10-bit 4:4:4,
# which mpv and VLC play but browsers, phones, and QuickTime do not; 8-bit
# 4:2:0 plays anywhere. If ffmpeg is missing or fails, the raw video is kept
# under the final name rather than lost.
#
# With "denoise", the sound is cleaned of steady background noise — the hiss
# and rumble of a laptop fan next to a built-in mic: a high-pass below 90 Hz
# for the rumble, then FFT noise reduction that tracks the noise floor. On a
# fan-noisy take it lowers the noise in pauses by about 12 dB and leaves the
# voice intact.

set -uo pipefail

video=$1
audio=$2
final=$3
denoise=${4:-}

duration() {
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null
}

have_audio=false
[[ -s $audio && -n $(duration "$audio") ]] && have_audio=true

encode() {
  local audio_in=() audio_out=()
  if $have_audio; then
    local skew
    skew=$(awk -v a="$(duration "$audio")" -v v="$(duration "$video")" 'BEGIN { printf "%.3f", a - v }')
    if awk -v s="$skew" 'BEGIN { exit !(s > 0) }'; then
      audio_in=(-ss "$skew" -i "$audio")
    else
      audio_in=(-itsoffset "${skew#-}" -i "$audio")
    fi
    audio_out=(-map 1:a -c:a aac -b:a 160k)
    [[ $denoise == denoise ]] && audio_out+=(-af "highpass=f=90,afftdn=nr=12:nf=-50:tn=1")
  fi
  ffmpeg -n -loglevel error -i "$video" "${audio_in[@]}" \
    -map 0:v -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    "${audio_out[@]}" -movflags +faststart -shortest "$final"
}

if command -v ffmpeg >/dev/null && encode; then
  rm -f "$video" "$audio"
else
  rm -f "$final"
  mv -n "$video" "$final"
  rm -f "$audio"
fi

[[ -e $final ]] || exit 1

if command -v notify-send >/dev/null; then
  notify-send -a "MIB Vlog" "Log entry saved" "$(basename "$final")"
fi
