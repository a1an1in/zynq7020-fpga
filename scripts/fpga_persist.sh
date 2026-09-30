#!/bin/sh
# fpga_persist.sh [mnt]  --  run ON THE BOARD.
# Replace the SD boot-partition system.bit with the new bit staged at /tmp/system_new.bit,
# so u-boot fetches THIS bit from the card on next boot (instead of the one in BOOT.BIN).
# - backs up the previous system.bit to system.bit.bak (safe to re-run / roll back)
# - checks uEnv.txt carries an 'fpga loadb' line (the u-boot payload) and warns if not
# Usage: sh /tmp/fpga_persist.sh [mountpoint]   (mountpoint optional; autodetected if omitted)
set -u

NEW=/tmp/system_new.bit
if [ ! -f "$NEW" ]; then
    echo "error: $NEW missing - upload the bit to the board first" >&2
    exit 2
fi

MNT=""
if [ -n "${1:-}" ]; then
    MNT="$1"
else
    for m in /media/sd-mmcblk0p1 /media/BOOT /media/boot /run/media/sd-mmcblk0p1 /mnt; do
        if [ -f "$m/uEnv.txt" ]; then MNT="$m"; break; fi
    done
fi

if [ -z "$MNT" ] || [ ! -f "$MNT/uEnv.txt" ]; then
    echo "error: SD boot partition not found (need a mounted FAT partition containing uEnv.txt)" >&2
    echo "       pass the mountpoint as an argument." >&2
    exit 3
fi

if grep -q 'fpga loadb' "$MNT/uEnv.txt"; then
    echo "  uEnv.txt: has fpga loadb -> u-boot should load the bit from this card  OK"
else
    echo "  WARN: uEnv.txt lacks a 'fpga loadb' line; u-boot will NOT pick this bit up from the card"
fi

if [ -f "$MNT/system.bit" ]; then
    cp -f "$MNT/system.bit" "$MNT/system.bit.bak" \
        && echo "  backup: system.bit -> system.bit.bak"
fi

if cp -f "$NEW" "$MNT/system.bit" && sync; then
    echo "  installed: $MNT/system.bit ($(wc -c < "$MNT/system.bit") B)"
else
    echo "error: failed to write $MNT/system.bit (is it read-only / full?)" >&2
    exit 4
fi

echo "  --- boot partition (relevant files) ---"
ls -l "$MNT" | grep -E 'system.bit|uEnv.txt|BOOT.BIN'
exit 0