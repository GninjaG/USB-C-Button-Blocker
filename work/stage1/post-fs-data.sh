#!/system/bin/sh
# Runs before Magisk/KernelSU mounts the module's system directory.
# Generating keylayouts here makes them part of THIS boot's mount.
MODDIR=${0%/*}
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

generate_analog_keylayouts >/dev/null 2>&1
exit 0
