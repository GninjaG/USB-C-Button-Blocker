#!/system/bin/sh
# Runs before Magisk/KernelSU mounts the module's system directory.
# Keep this stage minimal and fast: only repair SELinux labels on the payload.
# Do NOT generate keylayouts, run sync, or touch usbhid here. Those operations
# belong to service.sh / hotplug.sh, after Android has finished booting.
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *) MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) ;;
esac
[ -n "$MODDIR" ] || exit 0
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

fix_system_tree_contexts >/dev/null 2>&1
exit 0
