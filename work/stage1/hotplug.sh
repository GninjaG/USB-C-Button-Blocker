#!/system/bin/sh
# Called by inotifyd for each create event in /dev/input.
# $1 is the event mask and $2 is the filename; both are intentionally ignored.
MODDIR=${0%/*}
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

# Generate first: a separate HID-only audio device must expose its input name
# before we unbind usbhid and make that input node disappear.
unbind_usbhid_for_audio

exit 0
