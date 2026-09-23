#!/usr/bin/env bash
# Fetch one URL, with a hard ceiling on how much of the answer is read.
#
#   fetch.sh <max-seconds> <url> [curl options...]
#
# Prints the response body, or nothing and exits non-zero when the request
# fails, runs past <max-seconds>, or the body is larger than MAX_BYTES.
#
# Every network response the plugin parses comes through here, so a broken
# or compromised endpoint cannot make the shell or jq buffer an unbounded
# body. At most MAX_BYTES + 1 bytes are ever read: a body that reaches that
# extra byte is too large and is dropped before anything parses it. curl's
# --max-filesize stops such a download early too, but it is not trusted on
# its own, since a server can lie about or omit the length.
#
# The services answer in a few kilobytes at most; the ceiling leaves ample
# room.

set -uo pipefail

MAX_BYTES=65536

seconds=$1
url=$2
shift 2

body=$(mktemp) || exit 1
trap 'rm -f "$body"' EXIT

curl -fsS --max-time "$seconds" --max-filesize "$MAX_BYTES" "$@" "$url" 2>/dev/null |
  head -c $((MAX_BYTES + 1)) >"$body"
status=("${PIPESTATUS[@]}")

size=$(stat -c %s "$body") || exit 1
((size <= MAX_BYTES)) || exit 1
((status[0] == 0 && status[1] == 0)) || exit 1

cat "$body"
