#!/system/bin/sh
# Late-start service: event-driven hotplug guard plus keylayout refresh.
# There is intentionally no polling loop and no sleep loop.
MODDIR=${0%/*}
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

# Refresh generated keylayouts. At this stage the current mount is already
# built, so these files are for the NEXT reboot; unbind covers this session.
generate_all_keylayouts >/dev/null 2>&1

if command -v inotifyd >/dev/null 2>&1; then
  inotifyd "$MODDIR/hotplug.sh" /dev/input:c </dev/null >/dev/null 2>&1 &
else
  log_msg "inotifyd not found; hotplug guard disabled (keylayout layer remains)"
fi

# Immediate protection for an adapter already present at boot.
unbind_usbhid_for_audio

exit 0
