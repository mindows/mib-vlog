#!/usr/bin/env bash
# Fetch one URL, with a hard ceiling on how much of the answer is read.
#
#   FETCH_URL=<url> [FETCH_DATA=<body>] fetch.sh <max-seconds> [curl options...]
#
# Prints the response body, or nothing and exits non-zero when the request
# fails, runs past <max-seconds>, or the body is larger than MAX_BYTES. With
# FETCH_DATA the request is a POST of that body.
#
# Every network response the plugin parses comes through here, so a broken
# or compromised endpoint cannot make the shell or jq buffer an unbounded
# body. At most MAX_BYTES + 1 bytes are ever read: a body that reaches that
# extra byte is too large and is dropped before anything parses it. curl's
# --max-filesize stops such a download early too, but it is not trusted on
# its own, since a server can lie about or omit the length.
#
# The URL and body come in through the environment, not the command line,
# and reach curl through a file descriptor: they carry coordinates, a typed
# city, or nearby Wi-Fi access points, and any user on the machine can read
# a process's command line, while its environment is readable only by its
# owner. Only HTTPS is spoken: redirects are followed, at most three, and
# only to HTTPS.
#
# The services answer in a few kilobytes at most; the ceiling leaves ample
# room.

set -uo pipefail

MAX_BYTES=65536

seconds=$1
shift
url=${FETCH_URL:-}
[[ $url == https://* ]] || exit 1
data=${FETCH_DATA-}
has_data=${FETCH_DATA+yes}
unset FETCH_URL FETCH_DATA

body=$(mktemp) || exit 1
trap 'rm -f "$body"' EXIT

# curl's config syntax: a quoted string with \ and " escaped.
quoted=${url//\\/\\\\}
quoted=${quoted//\"/\\\"}
post=()
[[ -n $has_data ]] && post=(--data-binary @<(printf '%s' "$data"))

curl -fsS --max-time "$seconds" --max-filesize "$MAX_BYTES" \
  -L --proto =https --proto-redir =https --max-redirs 3 \
  --config <(printf 'url = "%s"\n' "$quoted") "${post[@]}" "$@" 2>/dev/null |
  head -c $((MAX_BYTES + 1)) >"$body"
status=("${PIPESTATUS[@]}")

size=$(stat -c %s "$body") || exit 1
((size <= MAX_BYTES)) || exit 1
((status[0] == 0 && status[1] == 0)) || exit 1

cat "$body"
