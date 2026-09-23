#!/usr/bin/env bash
# Join a finished take's parts into its final file.
#
#   finalize.sh <video> <audio> <final> [denoise] [hud-dir] [hud-offsets]
#
# <video> is Qt's recording (picture only) and <audio> is pw-record's WAV.
# They were started a moment apart but stopped together, so they are lined
# up by their ends: when the audio is longer its head is trimmed, and when
# it is shorter it is delayed, by the difference.
#
# The picture is cropped to the panel's 2:1 frame, keeping the bottom and
# cutting only the top, as the panel's preview does,
# and the HUD is burned in: <hud-dir> holds snapshots 000.png, 001.png, ...
# and <hud-offsets> the comma-separated seconds at which each takes over.
# A missing snapshot is skipped; the one before it simply runs longer.
#
# The video is re-encoded in any case: Qt's recorder writes H.264 in 10-bit
# 4:4:4, which mpv and VLC play but browsers, phones, and QuickTime do not;
# 8-bit 4:2:0 plays anywhere. If ffmpeg is missing or fails, the raw video
# is kept under the final name rather than lost.
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
hud_dir=${5:-}
hud_offsets=${6:-}

duration() {
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null
}

have_audio=false
[[ -s $audio && -n $(duration "$audio") ]] && have_audio=true

# The HUD snapshots as an ffconcat list: each image shown from its offset
# until the next one's. Prints the list's path, or nothing without any.
hud_list() {
  [[ -n $hud_dir && -d $hud_dir && -n $hud_offsets ]] || return 0
  local -a offsets files starts
  IFS=, read -ra offsets <<<"$hud_offsets"
  local i name
  for i in "${!offsets[@]}"; do
    printf -v name '%03d.png' "$i"
    [[ -s $hud_dir/$name ]] || continue
    files+=("$name")
    starts+=("${offsets[$i]}")
  done
  ((${#files[@]})) || return 0

  local list=$hud_dir/list.ffconcat
  {
    echo "ffconcat version 1.0"
    for i in "${!files[@]}"; do
      echo "file '${files[$i]}'"
      if ((i + 1 < ${#files[@]})); then
        awk -v a="${starts[$i]}" -v b="${starts[$((i + 1))]}" 'BEGIN { printf "duration %.3f\n", b - a }'
      fi
    done
    # The concat demuxer needs the last image twice for it to hold.
    echo "file '${files[-1]}'"
  } >"$list"
  echo "$list"
}

encode() {
  local inputs=(-i "$video") audio_out=() next=1
  if $have_audio; then
    local skew
    skew=$(awk -v a="$(duration "$audio")" -v v="$(duration "$video")" 'BEGIN { printf "%.3f", a - v }')
    if awk -v s="$skew" 'BEGIN { exit !(s > 0) }'; then
      inputs+=(-ss "$skew" -i "$audio")
    else
      inputs+=(-itsoffset "${skew#-}" -i "$audio")
    fi
    audio_out=(-map 1:a -c:a aac -b:a 160k)
    [[ $denoise == denoise ]] && audio_out+=(-af "highpass=f=90,afftdn=nr=12:nf=-50:tn=1")
    next=2
  fi

  # Crop to 2:1 from the bottom up, cutting only the top; even dimensions
  # for 4:2:0.
  local filter="[0:v]crop=trunc(iw/2)*2:trunc(iw/4)*2:0:ih-oh[frame]" out="[frame]"
  local list
  list=$(hud_list)
  if [[ -n $list ]]; then
    local w h
    IFS=x read -r w h < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
      -of csv=p=0:s=x "$video")
    w=$((w / 2 * 2))
    h=$((w / 4 * 2))
    inputs+=(-f concat -safe 0 -i "$list")
    filter+=";[$next:v]scale=$w:$h,format=rgba[hud];[frame][hud]overlay=eof_action=repeat:format=auto[burned]"
    out="[burned]"
  fi

  ffmpeg -n -loglevel error "${inputs[@]}" -filter_complex "$filter" \
    -map "$out" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    "${audio_out[@]}" -movflags +faststart -shortest "$final"
}

if command -v ffmpeg >/dev/null && encode; then
  rm -f "$video" "$audio"
else
  rm -f "$final"
  mv -n "$video" "$final"
  rm -f "$audio"
fi
[[ -n $hud_dir ]] && rm -rf "$hud_dir"

[[ -e $final ]] || exit 1

if command -v notify-send >/dev/null; then
  notify-send -a "MIB Vlog" "Log entry saved" "$(basename "$final")"
fi
