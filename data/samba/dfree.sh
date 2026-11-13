#!/bin/sh
set -eu

# Samba passes a directory (often ".") relative to its current working directory.
# Output: total blocks, available blocks for this user, bytes per block.
share_root=/shares
query=$(readlink -f "${1:-.}")

if [ "$query" = "$share_root" ]; then
    total_bytes=0
    available_bytes=0
    seen_devices=' '
    # Ignore ordinary folders and symlinks, including stale unplugged mountpoints.
    for candidate in "$share_root"/* "$share_root"/.[!.]* "$share_root"/..?*; do
        [ -d "$candidate" ] && [ ! -L "$candidate" ] || continue
        mountpoint -q "$candidate" || continue
        device=$(stat -c '%d' "$candidate") || continue
        # Bind aliases of the same filesystem must not inflate the total.
        case "$seen_devices" in *" $device "*) continue ;; esac
        capacity=$(stat -f -c '%b %a %S' "$candidate") || continue
        # Discard samples if the drive disappeared or changed during the query.
        mountpoint -q "$candidate" || continue
        current_device=$(stat -c '%d' "$candidate") || continue
        [ "$device" = "$current_device" ] || continue
        seen_devices="$seen_devices$device "

        # stat emits three integers. Normalize different filesystem block sizes.
        set -- $capacity
        total_bytes=$((total_bytes + $1 * $3))
        available_bytes=$((available_bytes + $2 * $3))
    done
    # Aggregate reporting only: files still have to fit on their destination drive.
    # No mounted drives means zero capacity, never the system card's capacity.
    printf '%s %s 1024\n' "$((total_bytes / 1024))" "$((available_bytes / 1024))"
    exit 0
fi

exec stat -f -c '%b %a %S' "$query"
