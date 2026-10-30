#!/system/bin/sh
# Runs before Magisk/KernelSU mounts the module's system directory.
# Keep this stage minimal and fast: only repair SELinux labels on the payload.
# Do NOT generate keylayouts, run sync, or touch usbhid here. Those operations
# belong to service.sh / hotplug.sh, after Android has finished booting.
case "$0" in
  */*) MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd -P) ;;
  *) MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) ;;
esac
[ -n "$MODDIR" ] || exit 0
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

purge_legacy_vendor >/dev/null 2>&1

_payload_ok=1
fix_system_tree_contexts >/dev/null 2>&1 || _payload_ok=0

if [ "$_payload_ok" -eq 1 ] && [ -d "$MODDIR/system" ]; then
  _has_kl=0
  for _klf in "$KL_DIR"/*.kl; do
    if [ -f "$_klf" ]; then
      _has_kl=1
      break
    fi
  done
  [ "$_has_kl" -eq 1 ] || _payload_ok=0
fi

if [ "$_payload_ok" -eq 0 ]; then
  # Fail closed: it is better to boot without the keylayout layer than to let
  # an inode with adb_data_file/ksu_file context be mounted over /system/usr.
  log_msg "SELinux payload verification failed; disabling system payload"
  if [ -f "$MODDIR/module.prop" ] && [ ! -L "$MODDIR" ]; then
    if [ -L "$MODDIR/system" ]; then
      rm -f "$MODDIR/system" 2>/dev/null
    elif [ -d "$MODDIR/system" ]; then
      rm -rf "$MODDIR/system.bad" 2>/dev/null
      mv "$MODDIR/system" "$MODDIR/system.bad" 2>/dev/null ||
        rm -rf "$MODDIR/system" 2>/dev/null
    fi
  fi
fi

exit 0
