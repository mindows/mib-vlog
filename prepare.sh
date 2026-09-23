#!/usr/bin/env bash
# Reserve a recording's file names.
#
#   prepare.sh <output-dir> <base>
#
# Creates the output directory, then prints two tab-separated paths: the
# final <base>.mp4 — or <base>-1.mp4, <base>-2.mp4, ... when that is taken —
# and the hidden file the recorder writes to until the take is finished.

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
printf '%s\t%s\n' "$final" "$dir/.$name.recording.mp4"
