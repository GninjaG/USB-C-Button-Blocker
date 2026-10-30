#!/system/bin/sh
# Late-start service: event-driven hotplug guard plus keylayout refresh.
# There is intentionally no polling loop and no sleep loop.
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *) MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) ;;
esac
[ -n "$MODDIR" ] || exit 0
umask 022

[ -r "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"

# Refresh generated keylayouts. At this stage the current mount is already
# built, so these files are for the NEXT reboot; unbind covers this session.
generate_all_keylayouts >/dev/null 2>&1

PIDFILE="$MODDIR/.inotifyd.pid"
INOTIFY_LOG="$MODDIR/inotifyd.log"

start_watcher() {
  if [ -f "$PIDFILE" ]; then
    _sw_pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$_sw_pid" ] && [ -d "/proc/$_sw_pid" ] &&
       [ "$(cat "/proc/$_sw_pid/comm" 2>/dev/null)" = "inotifyd" ]; then
      return 0
    fi
  fi

  if ! command -v inotifyd >/dev/null 2>&1; then
    log_msg "inotifyd not found; hotplug guard disabled (keylayout layer remains)"
    return 1
  fi

  # Toybox and BusyBox both use n = IN_CREATE for a watched directory.
  # /dev/input is devtmpfs, where create events are reliable; sysfs/kernfs
  # behavior varies by kernel, so do not depend on it.
  : > "$INOTIFY_LOG" 2>/dev/null
  chmod 0644 "$INOTIFY_LOG" 2>/dev/null

  if command -v nohup >/dev/null 2>&1; then
    nohup inotifyd "$MODDIR/hotplug.sh" /dev/input:n </dev/null >>"$INOTIFY_LOG" 2>&1 &
  else
    inotifyd "$MODDIR/hotplug.sh" /dev/input:n </dev/null >>"$INOTIFY_LOG" 2>&1 &
  fi

  _sw_new=$!
  printf '%s\n' "$_sw_new" > "$PIDFILE" 2>/dev/null
  chmod 0644 "$PIDFILE" 2>/dev/null

  if kill -0 "$_sw_new" 2>/dev/null; then
    log_msg "inotifyd watcher started (pid $_sw_new, mask n)"
  else
    log_msg "inotifyd exited immediately; see $INOTIFY_LOG"
    rm -f "$PIDFILE" 2>/dev/null
    return 1
  fi
  return 0
}

# Start watching before the initial scan so a device inserted during the
# scan cannot fall into a gap.
start_watcher

# Immediate protection for an adapter already present at boot.
unbind_usbhid_for_audio

exit 0
