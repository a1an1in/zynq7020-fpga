#!/bin/sh
# fpga_persist.sh -- persist /tmp/system_new.bit as system.bit in the SD boot
# partition (FAT) so that u-boot (uEnv.txt 'fatload system.bit ; fpga loadb ...')
# loads THIS bit on next reboot. Kept intentionally POSIX/busybox-ash friendly.
#
# Uploaded to the board by `scripts/fpga.py load` and then invoked as:
#     sh /tmp/fpga_persist.sh '<mnt>'        # <mnt> optional, auto-detected
#
# Doesn't touch BOOT.BIN; the running PL is unaffected until a reboot.
set -u

SRC=/tmp/system_new.bit
mnt="${1:-}"

die() { echo "[fpga_persist:error] $*" >&2; exit 1; }

# 0) sanity: the freshly uploaded bit must exist and be non-empty
[ -f "$SRC" ] && [ -s "$SRC" ] || die "missing uploaded $SRC"

# 1) locate the SD boot (FAT) partition mountpoint
if [ -z "$mnt" ] || [ ! -d "$mnt" ]; then
    mnt=""
    # 1a) boot partition already mounted (e.g. automount /media/sd-*, /mnt/sd-*)?
    while read -r _dev _mp _fs _rest; do
        case "$_fs" in
            vfat|msdos|fat)
                case "$_dev" in
                    /dev/mmcblk*p1|/dev/mmcblk*1) mnt="$_mp"; break ;;
                esac ;;
        esac
    done < /proc/mounts
fi

# 1b) try auto-mount if not mounted (this board: boot = mmcblk*p1)
if [ -z "$mnt" ] || [ ! -d "$mnt" ]; then
    for d in /dev/mmcblk0p1 /dev/mmcblk1p1 /dev/mmcblk2p1; do
        [ -b "$d" ] || continue
        mkdir -p /mnt/fpga_persist
        if mount "$d" /mnt/fpga_persist >/dev/null 2>&1 && [ -d /mnt/fpga_persist ]; then
            mnt=/mnt/fpga_persist
            break
        fi
    done
fi

[ -n "$mnt" ] && [ -d "$mnt" ] || die "cannot find SD boot mountpoint (pass --mnt <path>)"

# 2) backup once, then atomically replace system.bit
dst="$mnt/system.bit"
if [ -f "$dst" ] && [ ! -e "$dst.bak" ]; then
    cp -f "$dst" "$dst.bak" 2>/dev/null || true
    echo "[fpga_persist] backup: $dst -> $dst.bak"
fi

cp -f "$SRC" "$dst" || die "copy $SRC -> $dst failed"
sync

size=$(wc -c < "$dst" 2>/dev/null || echo 0)
echo "[fpga_persist:ok] $SRC -> $dst (${size} B)"
echo "[fpga_persist:ok] reboot now; u-boot will 'fpga loadb' system.bit from the card"