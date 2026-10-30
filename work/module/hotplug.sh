#!/system/bin/sh
# Called by inotifyd for /dev/input:n (directory entry created).
# inotifyd passes: $1=events, $2=watched path, $3=filename. All are ignored.
case "$0" in
  */*) MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd -P) ;;
  *) MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) ;;
esac
[ -n "$MODDIR" ] || exit 0
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

# Serialize overlapping create events without polling. If flock is absent the
# scan is still idempotent, so this is a best-effort optimization only.
if command -v flock >/dev/null 2>&1; then
  if { : 9>"$MODDIR/.hotplug.lock"; } 2>/dev/null; then
    # Bounded wait; if -w is unsupported or the lock is busy, proceed
    # unlocked rather than blocking the inotifyd handler forever.
    flock -w 5 9 2>/dev/null || flock -n 9 2>/dev/null || true
  fi
fi

# Generate first: a separate HID-only audio device must expose its input name
# before we unbind usbhid and make that input node disappear. Files generated
# after the current mount are for the next reboot; unbind is this session.
generate_all_keylayouts >/dev/null 2>&1
unbind_usbhid_for_audio

exit 0
