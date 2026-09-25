#!/usr/bin/env bash
# Join a finished take's parts into its final file.
#
#   MIBVLOG_TAKE=<take-json> finalize.sh <video> <audio> <final> [denoise] [hud-dir] [hud-offsets] [mirror] [unused] [transcribe] [work-dir]
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
# With "mirror", the picture is flipped left to right, as the preview shows
# it, before the HUD goes on, so the HUD still reads normally.
#
# The video is re-encoded in any case: Qt's recorder writes H.264 in 10-bit
# 4:4:4, which mpv and VLC play but browsers, phones, and QuickTime do not;
# 8-bit 4:2:0 plays anywhere. If ffmpeg is missing or fails, the raw video
# is kept instead rather than lost.
#
# <final> is the name prepare.sh found free when the take started, but it is
# not reserved: another file may have taken it since. So the take is encoded
# into a hidden file of its own and then moved into place with a rename that
# refuses to replace anything. If <final> is taken, the take goes to the first
# free <final>-1.mp4, <final>-2.mp4, ... and the other file is left alone.
# Nothing here ever deletes or overwrites a file this script did not create.
#
# <work-dir> is the take's own directory from prepare.sh (mktemp -d), which
# holds <video>, <audio>, and <hud-dir>. Once the take is in place it is
# removed as a whole, and it is the only directory this script removes: a
# path that is not a take's work directory beside <final> is left alone.
#
# <take-json> describes the take (start time, place, host, conditions). It
# comes in through the environment (MIBVLOG_TAKE), not the command line,
# because it can hold the place, and any user on the machine can read a
# process's command line; its environment only its owner can. For the same
# reason the tags reach ffmpeg in a private ffmetadata file, not as
# -metadata arguments. The take is written into the file's metadata, with the duration added here: the
# standard creation date and ISO 6709 location that photo libraries read,
# a title and one-line summary for players, and every field under mibvlog.*.
# The place, coordinates, and hostname are left out unless the take's
# tagLocation is true.
#
# With "transcribe", once the video is saved its sound is transcribed with
# voxtype (Omarchy's local Whisper, using whatever model voxtype is
# configured for) into a Markdown file beside it: <final> with .md for .mp4.
# Without voxtype, or for a take with no sound, there is no transcript.
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
mirror=${7:-}
take_json=${MIBVLOG_TAKE:-"{}"}
unset MIBVLOG_TAKE
want_transcript=${9:-}
work=${10:-}

# A take's work directory: .<name>.XXXXXX (mktemp -d) in the same folder as
# <final>, holding the recording. Anything else is not ours to remove.
is_work_dir() {
  [[ -n $work && -d $work && ! -L $work ]] || return 1
  [[ ${work%/*} == "${final%/*}" && ${work##*/} =~ ^\..+\.[A-Za-z0-9]{6}$ ]] || return 1
  [[ $video == "$work"/* ]]
}

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

# The take's tags as ffmetadata lines (key=value, with =, ;, #, \ and
# newlines escaped). Empty fields are left out.
take_metadata() {
  local length
  length=$(duration "$video")
  jq -r --argjson seconds "${length:-0}" '
    def two: tostring | if length < 2 then "0" + . else . end;
    # ISO 6709 coordinate: signed degrees to four decimals (about 10 m).
    def coord: (if . >= 0 then "+" else "" end) + (. * 10000 | round / 10000 | tostring);
    def esc: tostring | gsub("(?<c>[=;#\\\\\n])"; "\\\(.c)");
    def put($key; $value): if ($value // "") == "" then empty else "\($key)=\($value | esc)" end;

    # Without tagLocation, where the take was made stays out of the file.
    (if .tagLocation == true then . else .location = "" | .latitude = null
      | .longitude = null | .hostname = "" end)
    | ($seconds | floor) as $whole
    | "\($whole / 3600 | floor | two):\($whole % 3600 / 60 | floor | two):\($whole % 60 | two)" as $hms
    | (.latitude != null and .longitude != null) as $placed
    | ([.weather, .temperature] | map(select(. != "")) | join(" ")) as $conditions
    | put("title"; .title),
      # Whole seconds: the MP4 header keeps its own whole-second copy of this,
      # and ffprobe shows both, so they should name the same instant.
      put("creation_time"; .startUtc | sub("\\.[0-9]+Z$"; "Z")),
      put("com.apple.quicktime.creationdate"; .startLocal),
      put("com.apple.quicktime.location.ISO6709";
        if $placed then (.latitude | coord) + (.longitude | coord) + "/" else "" end),
      put("comment"; ["SOL " + .sol, .location, $conditions, (if .aqi != "" then "AQI " + .aqi else "" end)]
        | map(select(. != "")) | join(" | ")),
      put("mibvlog.start"; .startLocal),
      put("mibvlog.duration"; $hms),
      put("mibvlog.duration_seconds"; $seconds * 1000 | round / 1000 | tostring),
      put("mibvlog.location"; .location),
      put("mibvlog.latitude"; if $placed then .latitude | tostring else "" end),
      put("mibvlog.longitude"; if $placed then .longitude | tostring else "" end),
      put("mibvlog.hostname"; .hostname),
      put("mibvlog.weather"; .weather),
      put("mibvlog.temperature"; .temperature),
      put("mibvlog.aqi"; .aqi),
      put("mibvlog.sol"; .sol),
      put("mibvlog.log_entry"; .logEntry)
  ' <<<"$take_json" 2>/dev/null
}

encode() {
  local output=$1
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
  local flip=""
  [[ $mirror == mirror ]] && flip=",hflip"
  local filter="[0:v]crop=trunc(iw/2)*2:trunc(iw/4)*2:0:ih-oh$flip[frame]" out="[frame]"
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

  # The tags go in as one more input, an ffmetadata file (mktemp: mode
  # 0600), and only its tags are kept: none from the raw recording or its
  # streams. -y is safe: <output> is the hidden file made for this take.
  local meta arg meta_input=0 status
  meta=$(mktemp) || return 1
  { echo ";FFMETADATA1"; take_metadata; } >"$meta"
  for arg in "${inputs[@]}"; do [[ $arg == -i ]] && meta_input=$((meta_input + 1)); done
  inputs+=(-f ffmetadata -i "$meta")

  ffmpeg -y -loglevel error "${inputs[@]}" -filter_complex "$filter" \
    -map "$out" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    "${audio_out[@]}" -map_metadata "$meta_input" -map_metadata:s -1 -map_chapters -1 \
    -movflags +faststart+use_metadata_tags -shortest -f mp4 "$output"
  status=$?
  rm -f "$meta"
  return $status
}

# Moves <file> to $final, or to the first free $final-1.mp4, $final-2.mp4, ...
# when something else holds that name, and points $final at where it landed.
# --update=none-fail is a single rename that fails rather than replace an
# existing file, so a name taken at the last moment is still never clobbered.
place() {
  local src=$1 stem=${final%.mp4} candidate=$final n=1
  until mv --update=none-fail -- "$src" "$candidate" 2>/dev/null; do
    # Only a taken name moves on to the next one; any other failure stops.
    [[ -e $candidate || -L $candidate ]] || return 1
    ((n < 1000)) || return 1
    candidate=$stem-$n.mp4
    n=$((n + 1))
  done
  final=$candidate
}

encoded=$(mktemp "${final%/*}/.$(basename "$final" .mp4).encoding.XXXXXX") || encoded=""
# The size check backs up ffmpeg's exit status, which is not always a
# reliable sign that a file was written.
if [[ -n $encoded ]] && command -v ffmpeg >/dev/null && encode "$encoded" && [[ -s $encoded ]] &&
  place "$encoded"; then
  rm -f "$video" "$audio"
else
  [[ -n $encoded ]] && rm -f "$encoded"
  # The raw video instead; if even that cannot be placed, the hidden
  # recording stays where it is rather than being lost.
  place "$video" || exit 1
  rm -f "$audio"
fi
# The take is in place: its work directory (sound, snapshots, lists) goes.
is_work_dir && rm -rf -- "$work"

if command -v notify-send >/dev/null; then
  notify-send -a "MIB Vlog" "Log entry saved" "$(basename "$final")"
fi

# Whatever voxtype says after its "Processing N samples" line is the text.
transcribe() {
  local wav
  wav=$(mktemp --suffix .wav) || return 1
  ffmpeg -v error -y -i "$final" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav" &&
    voxtype -q transcribe "$wav" 2>/dev/null |
    awk 'found { print; next } /^Processing [0-9]+ samples/ { found = 1 }' |
      sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}'
  local status=$?
  rm -f "$wav"
  return $status
}

# The video embedded at the top (Obsidian's ![[...]] link, which resolves by
# file name), a heading and one line of context, the text, and the
# conditions the take was recorded in at the end. noclobber: if a file
# already has the transcript's name, it is left alone and no transcript is
# written.
write_transcript() (
  set -o noclobber
  local text=$1 transcript=${final%.mp4}.md length
  length=$(duration "$final")
  {
    printf '![[%s]]\n\n' "$(basename "$final")"
    jq -r --arg length "${length:-0}" '
      def when: (.startLocal // "") | sub("T"; " ") | .[0:16];
      "# \(.title // "Log entry")\n",
      ([when, (if .sol then "SOL " + .sol else "" end), (.location // ""),
        ($length | tonumber | . * 10 | round / 10 | tostring) + " s"]
        | map(select(. != "")) | join(" · ")),
      ""
    ' <<<"$take_json" 2>/dev/null || printf '# Log entry\n\n'
    if [[ -n $text ]]; then
      printf '%s\n' "$text"
    else
      printf '_No speech detected._\n'
    fi
    jq -r '
      [ (if (.weather // "") != "" then "- Weather: " + .weather else empty end),
        (if (.temperature // "") != "" then "- Temp: " + .temperature else empty end),
        (if (.aqi // "") != "" then "- AQI: " + .aqi else empty end) ]
      | if length > 0 then "\n## Environment\n\n" + join("\n") else empty end
    ' <<<"$take_json" 2>/dev/null
  } 2>/dev/null >"$transcript"
)

if [[ $want_transcript == transcribe ]] && $have_audio && command -v voxtype >/dev/null; then
  text=$(transcribe) && write_transcript "$text"
fi
