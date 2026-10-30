#!/system/bin/sh
# Runs before Magisk/KernelSU mounts the module's system directory.
# Generating keylayouts here makes them part of THIS boot's mount.
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *) MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) ;;
esac
[ -n "$MODDIR" ] || exit 0
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

generate_all_keylayouts >/dev/null 2>&1
sync 2>/dev/null

# Early guard: if usbhid is already bound before Android input starts, kill the
# adapter's HID interface now. service.sh repeats this for hotplug.
unbind_usbhid_for_audio >/dev/null 2>&1

exit 0
