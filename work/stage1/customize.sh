#!/system/bin/sh
# Installation customization only. Adapter detection is deliberately done at
# runtime so any USB-C audio adapter works, including future devices.

ui_print "- USB-C Button Blocker"
ui_print "- Layer 1: event-driven usbhid unbind for USB audio adapters"
ui_print "- Layer 2: automatic keylayout generation (USB + analog jacks)"
ui_print "- No adapter needs to be connected during installation"

if [ -z "${MODPATH:-}" ]; then
  abort "! MODPATH is not set"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
for _f in customize.sh common.sh post-fs-data.sh service.sh hotplug.sh; do
  if [ -f "$MODPATH/$_f" ]; then
    set_perm "$MODPATH/$_f" 0 0 0755
  fi
done

ui_print "- Reboot to activate"
