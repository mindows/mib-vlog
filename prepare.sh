#!/usr/bin/env bash
# Reserve a recording's file names.
#
#   prepare.sh <output-dir> <base>
#
# Creates the output directory, then prints three tab-separated fields: the
# final <base>.mp4 — or <base>-1.mp4, <base>-2.mp4, ... when that is taken —
# the hidden file the recorder writes to until the take is finished, and the
# system's current default microphone (a PipeWire source name, possibly
# empty), which the take records from.

set -euo pipefail

dir=$1
base=$2

mkdir -p "$dir"

final="$dir/$base.mp4"
n=1
while [[ -e $final ]]; do
  final="$dir/$base-$n.mp4"
  n=$((n + 1))
done

name=$(basename "$final" .mp4)
mic=$(pactl get-default-source 2>/dev/null || true)
printf '%s\t%s\t%s\n' "$final" "$dir/.$name.recording.mp4" "$mic"
