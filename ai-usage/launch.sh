#!/usr/bin/env bash
# Start the usage widget.
#
#   launch.sh         autostart: on a fresh boot, wait until the system has been
#                     up for AI_USAGE_BOOT_DELAY seconds (default 300) first
#   launch.sh --now   start immediately with the details popup open
#
# Only one instance runs at a time (qs -n), so an early --now start makes the
# delayed autostart a no-op.

set -u

widget_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--now" ]]; then
    export AI_USAGE_OPEN=1
else
    boot_delay="${AI_USAGE_BOOT_DELAY:-300}"
    uptime_seconds="$(cut -d. -f1 /proc/uptime)"
    if (( uptime_seconds < boot_delay )); then
        sleep "$(( boot_delay - uptime_seconds ))"
    fi
fi

exec qs -n -p "$widget_dir"
