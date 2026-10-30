#!/system/bin/sh
# Called by inotifyd for /dev/input:n (directory entry created).
# $1 is the event mask and $2 is the filename; both are intentionally ignored.
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *) MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) ;;
esac
[ -n "$MODDIR" ] || exit 0
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

# Generate first: a separate HID-only audio device must expose its input name
# before we unbind usbhid and make that input node disappear. Files generated
# after the current mount are for the next reboot; unbind is this session.
generate_all_keylayouts >/dev/null 2>&1
unbind_usbhid_for_audio

exit 0
