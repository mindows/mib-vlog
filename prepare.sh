#!/usr/bin/env bash
# Reserve a recording's file names.
#
#   prepare.sh <output-root> <base>
#
# Takes are filed by month: <output-root>/YYYYMM/, the month taken from the
# base name (YYYYMMDD-...) so folder and file always agree. Creates that
# directory, then prints five tab-separated fields: the
# final <base>.mp4 — or <base>-1.mp4, <base>-2.mp4, ... when that is taken —
# the file the recorder writes to until the take is finished, the system's
# current default microphone (a PipeWire source name, possibly empty), which
# the take records from, the directory for the HUD snapshots burned into the
# take, and the take's work directory, which holds the other two.
#
# The work directory is made fresh by mktemp -d (.<name>.XXXXXX, mode 0700),
# so it never reuses a path that already exists, and everything the take
# writes before it is finished lives inside it. Cleaning up a take removes
# that directory and nothing else. The final name is only a suggestion:
# finalize.sh moves the take to the next free name if it has been taken since.

set -euo pipefail

root=$1
base=$2
dir="$root/${base:0:6}"

mkdir -p "$dir"

final="$dir/$base.mp4"
n=1
while [[ -e $final ]]; do
  final="$dir/$base-$n.mp4"
  n=$((n + 1))
done

name=$(basename "$final" .mp4)
mic=$(pactl get-default-source 2>/dev/null || true)
work=$(mktemp -d "$dir/.$name.XXXXXX")
mkdir "$work/hud"
printf '%s\t%s\t%s\t%s\t%s\n' "$final" "$work/recording.mp4" "$mic" "$work/hud" "$work"
