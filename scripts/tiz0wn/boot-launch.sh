#!/bin/sh
# One-shot boot/start action modelled after tiz0wn's app-start worker.
# Run on the owned TV only from a validated root agent/boot hook. Not installed automatically.
# Usage: sh boot-launch.sh check APP_ID | start APP_ID
set -eu
mode=${1:-}
app=${2:-}
case "$mode" in check|start) ;; *) echo 'usage: boot-launch.sh check|start APP_ID' >&2; exit 2 ;; esac
printf '%s\n' "$app" | grep -Eq '^[A-Za-z0-9]{10}\.[A-Za-z0-9_-]{1,52}$' || { echo 'invalid SDK app ID' >&2; exit 2; }
[ -x /usr/bin/app_launcher ] || { echo 'Tizen app_launcher unavailable' >&2; exit 65; }
command -v timeout >/dev/null 2>&1 || { echo 'No timeout utility; refusing an unbounded boot launch' >&2; exit 65; }
printf 'app_launcher present; target %s; mode %s\n' "$app" "$mode"
[ "$mode" = start ] || exit 0
[ "$(id -u)" = 0 ] || { echo 'Boot launch requires a verified root channel' >&2; exit 65; }
# Boot scripts must not block the Tizen startup path or run indefinitely.
attempt=1
while [ "$attempt" -le 3 ]; do
    output=$(timeout 12 /usr/bin/app_launcher -s "$app" 2>&1) && {
        printf 'launch attempt %s: %s\n' "$attempt" "$output"
        exit 0
    }
    printf 'launch attempt %s failed: %s\n' "$attempt" "$output" >&2
    attempt=$((attempt + 1))
    [ "$attempt" -le 3 ] && sleep 5
done
echo 'DansTV launch failed; leave Samsung startup untouched' >&2
exit 65
