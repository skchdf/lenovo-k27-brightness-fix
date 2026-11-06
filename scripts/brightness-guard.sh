#!/usr/bin/env bash
# Keep the panel backlight above zero.
#
# Why: intel_backlight brightness=0 really turns the panel off, while KDE's
# slider happily allows 0. This guard raises 0 back to a small visible floor.
#
# This script is OPTIONAL. It was evaluated but NOT installed on the reference
# machine; the owner chose to simply keep the slider at least one notch above 0.
#
# Install:
#   sudo install -m 755 scripts/brightness-guard.sh /usr/local/bin/
#   sudo install -m 644 scripts/brightness-guard.service /etc/systemd/system/
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now brightness-guard.service
#
# Tunables (environment variables):
#   BACKLIGHT_DEV=/sys/class/backlight/intel_backlight
#   MIN_PERCENT=5     # floor, in percent of max_brightness
#   INTERVAL=2        # polling interval in seconds

set -u

DEV="${BACKLIGHT_DEV:-/sys/class/backlight/intel_backlight}"
MIN_PERCENT="${MIN_PERCENT:-5}"
INTERVAL="${INTERVAL:-2}"

log() {
    if command -v logger >/dev/null 2>&1; then
        logger -t brightness-guard -- "$*"
    else
        printf '%s\n' "$*" >&2
    fi
}

if [ ! -d "$DEV" ]; then
    log "backlight device not found: $DEV"
    exit 1
fi

if ! max=$(cat "$DEV/max_brightness" 2>/dev/null) || ! [[ "$max" =~ ^[0-9]+$ ]] || [ "$max" -le 0 ]; then
    log "cannot read a valid max_brightness from $DEV"
    exit 1
fi

if ! [[ "$MIN_PERCENT" =~ ^[0-9]+$ ]]; then
    log "MIN_PERCENT must be an integer, got: $MIN_PERCENT"
    exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
    log "INTERVAL must be a positive integer, got: $INTERVAL"
    exit 1
fi

floor=$(( max * MIN_PERCENT / 100 ))
[ "$floor" -lt 1 ] && floor=1

log "started: dev=$DEV max=$max floor=$floor (${MIN_PERCENT}%) interval=${INTERVAL}s"

while :; do
    cur=$(cat "$DEV/brightness" 2>/dev/null || true)
    case "$cur" in
        ''|*[!0-9]*)
            # Device temporarily unavailable or a non-numeric value; retry.
            ;;
        0)
            if echo "$floor" > "$DEV/brightness" 2>/dev/null; then
                log "brightness was 0, raised to $floor"
            else
                log "brightness was 0, but writing $floor failed"
            fi
            ;;
    esac
    sleep "$INTERVAL"
done
