#!/usr/bin/env sh
# build_usb_blocker.sh
# Gera o modulo KernelSU/Magisk "usb_c_button_blocker.zip" no diretorio atual.
#
# Uso:
#   sh build_usb_blocker.sh [caminho_de_saida.zip]
#
# Requisitos: sh POSIX e (zip OU python3). Em Termux:
#   pkg install zip        # opcional, se python nao estiver instalado
#
# O ZIP e montado com module.prop e META-INF na raiz, sem pasta externa.

set -eu
umask 022

OUT=${1:-"$PWD/usb_c_button_blocker.zip"}
case "$OUT" in
  /*) ;;
  *) OUT="$PWD/$OUT" ;;
esac

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/usb_c_button_blocker.XXXXXX" 2>/dev/null || true)
if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="${TMPDIR:-/tmp}/usb_c_button_blocker.$$"
  mkdir -p "$BUILD_DIR"
fi
case "$BUILD_DIR" in
  ''|'/'|'.') echo "ERRO: diretorio temporario invalido" >&2; exit 1 ;;
esac

cleanup() {
  [ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"
}
trap cleanup 0 1 2 15

mkdir -p "$BUILD_DIR/META-INF/com/google/android"

printf '%s\n' "- Criando arquivos do modulo em $BUILD_DIR"

cat > "$BUILD_DIR/module.prop" <<'__USB_BLOCKER_FILE_EOF__'
id=usb_c_button_blocker
name=USB-C Button Blocker
version=1.0.0
versionCode=1
author=Vitor
description=Blocks phantom volume/media buttons from USB-C audio adapters and analog headset jacks at runtime, preserving DAC audio, physical gpio-keys and Bluetooth AVRCP.
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/customize.sh" <<'__USB_BLOCKER_FILE_EOF__'
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

# Create the static analog-jack layouts now. This intentionally does NOT look
# at USB devices or at the currently connected adapter; it only copies the
# phone's own Generic.kl so the first boot already has a system payload.
# It runs after set_perm_recursive so the generated files get explicit modes
# and SELinux contexts from write_blocked_kl.
if [ -r "$MODPATH/common.sh" ]; then
  MODDIR="$MODPATH"
  . "$MODPATH/common.sh"
  generate_static_analog_keylayouts >/dev/null 2>&1
fi

if [ "${KSU:-}" = "true" ]; then
  ui_print "- KernelSU detected"
  ui_print "- Keylayout layer: install meta-overlayfs so /system can be mounted"
  ui_print "- Runtime usbhid unbind layer works without a metamodule"
fi

ui_print "- Reboot to activate"
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/common.sh" <<'__USB_BLOCKER_FILE_EOF__'
#!/system/bin/sh
# Shared helpers for USB-C Button Blocker.
# POSIX sh + Android toybox/busybox only. No bashisms, no polling loops.

MODDIR=${MODDIR:-${0%/*}}
KL_DIR="$MODDIR/system/usr/keylayout"
KL_VENDOR_DIR="$MODDIR/system/vendor/usr/keylayout"

# Overridable only to make the logic testable on a host; production uses sysfs.
USB_DEVICES_DIR="${USB_DEVICES_DIR:-/sys/bus/usb/devices}"
USBHID_DRIVER_DIR="${USBHID_DRIVER_DIR:-/sys/bus/usb/drivers/usbhid}"
USBHID_UNBIND_FILE="${USBHID_UNBIND_FILE:-/sys/bus/usb/drivers/usbhid/unbind}"
INPUT_DEVICES_FILE="${INPUT_DEVICES_FILE:-/proc/bus/input/devices}"
KEYLAYOUT_SOURCE="${KEYLAYOUT_SOURCE:-}"

log_msg() {
  if command -v log >/dev/null 2>&1; then
    log -t USBButtonBlocker "$*" 2>/dev/null
  fi
}

to_lower() {
  printf '%s' "$1" | tr 'A-Z' 'a-z'
}

is_hex4() {
  case "$1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
  esac
  return 1
}

canonical_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'
}

is_audio_input_name() {
  case "$1" in
    *usb*audio*|*audio*usb*|*cx31993*|*cb1200*|*realtek*|*alc[0-9]*|*kt02*|*savitech*|*dac*|*type-c*|*usb-c*|*usb\ c*|*headset*|*headphone*|*audio*adapter*)
      return 0
      ;;
  esac
  return 1
}

find_generic_kl() {
  if [ -n "$KEYLAYOUT_SOURCE" ] && [ -f "$KEYLAYOUT_SOURCE" ] && [ -r "$KEYLAYOUT_SOURCE" ]; then
    printf '%s\n' "$KEYLAYOUT_SOURCE"
    return 0
  fi
  for _p in \
    /system/usr/keylayout/Generic.kl \
    /system_ext/usr/keylayout/Generic.kl \
    /vendor/usr/keylayout/Generic.kl \
    /product/usr/keylayout/Generic.kl \
    /odm/usr/keylayout/Generic.kl \
    /system_root/system/usr/keylayout/Generic.kl
  do
    if [ -f "$_p" ] && [ -r "$_p" ]; then
      printf '%s\n' "$_p"
      return 0
    fi
  done
  return 1
}

# A device/analog-specific .kl may already exist and contain OEM mappings that
# are not in Generic.kl. Use it as the base when available, in AOSP lookup
# order, and fall back to Generic.kl.
find_base_kl() {
  _fb_name=$1
  for _fb_dir in \
    /product/usr/keylayout \
    /system_ext/usr/keylayout \
    /odm/usr/keylayout \
    /vendor/usr/keylayout \
    /system/usr/keylayout
  do
    if [ -f "$_fb_dir/$_fb_name.kl" ] && [ -r "$_fb_dir/$_fb_name.kl" ]; then
      printf '%s\n' "$_fb_dir/$_fb_name.kl"
      return 0
    fi
  done
  find_generic_kl
}

# Print the source keylayout with the six offending key codes commented out.
# awk is present in Android toybox and in Magisk/KernelSU busybox; the pure-sh
# fallback covers unusually stripped environments. The fallback runs in a
# subshell so set -f / set -- cannot leak to the caller.
filter_keys() {
  _fk_src=$1
  if command -v awk >/dev/null 2>&1; then
    awk '
      /^[[:space:]]*#/ { print; next }
      {
        if ($1 == "key" && ($2 == 114 || $2 == 115 || $2 == 163 || $2 == 164 || $2 == 165 || $2 == 226))
          print "#" $0
        else
          print
      }
    ' "$_fk_src"
    return 0
  fi

  (
    set -f
    while IFS= read -r _fk_line || [ -n "$_fk_line" ]; do
      set -- $_fk_line
      case "${1:-}:${2:-}" in
        key:114|key:115|key:163|key:164|key:165|key:226)
          printf '#%s\n' "$_fk_line"
          ;;
        *)
          printf '%s\n' "$_fk_line"
          ;;
      esac
    done < "$_fk_src"
  )
  return 0
}

ensure_kl_dir() {
  _ek_primary=0
  for _ek_d in "$KL_DIR" "$KL_VENDOR_DIR"; do
    if mkdir -p "$_ek_d" 2>/dev/null; then
      chmod 0755 "$_ek_d" 2>/dev/null
      chown 0:0 "$_ek_d" 2>/dev/null
      case "$_ek_d" in
        "$KL_VENDOR_DIR") _ek_con=u:object_r:vendor_file:s0 ;;
        *) _ek_con=u:object_r:system_file:s0 ;;
      esac
      chcon "$_ek_con" "$_ek_d" 2>/dev/null
      [ "$_ek_d" = "$KL_DIR" ] && _ek_primary=1
    fi
  done
  [ "$_ek_primary" -eq 1 ]
}

write_blocked_kl() {
  _kl_name=$1
  _kl_generic=$2
  [ -n "$_kl_name" ] || return 1

  _kl_base=$(find_base_kl "$_kl_name" 2>/dev/null || true)
  if [ -z "$_kl_base" ] || [ ! -f "$_kl_base" ] || [ ! -r "$_kl_base" ]; then
    _kl_base=$_kl_generic
  fi
  [ -f "$_kl_base" ] && [ -r "$_kl_base" ] || return 1

  mkdir -p "$KL_DIR" 2>/dev/null || return 1
  _kl_seed="$MODDIR/.klseed.$$.$_kl_name"

  {
    printf '# Generated by usb_c_button_blocker - do not edit\n'
    filter_keys "$_kl_base"
  } > "$_kl_seed" 2>/dev/null || {
    rm -f "$_kl_seed"
    return 1
  }

  _kl_written=0
  for _kl_dir in "$KL_DIR" "$KL_VENDOR_DIR"; do
    mkdir -p "$_kl_dir" 2>/dev/null || continue
    chmod 0755 "$_kl_dir" 2>/dev/null
    chown 0:0 "$_kl_dir" 2>/dev/null
    case "$_kl_dir" in
      "$KL_VENDOR_DIR") _kl_con=u:object_r:vendor_file:s0 ;;
      *) _kl_con=u:object_r:system_file:s0 ;;
    esac
    chcon "$_kl_con" "$_kl_dir" 2>/dev/null

    _kl_out="$_kl_dir/$_kl_name.kl"
    _kl_tmp="$_kl_dir/.$_kl_name.kl.$$"
    cp -f "$_kl_seed" "$_kl_tmp" 2>/dev/null || {
      rm -f "$_kl_tmp"
      continue
    }

    if [ -f "$_kl_out" ] && cmp -s "$_kl_tmp" "$_kl_out" 2>/dev/null; then
      rm -f "$_kl_tmp"
      _kl_written=1
      continue
    fi

    if mv -f "$_kl_tmp" "$_kl_out" 2>/dev/null; then
      chmod 0644 "$_kl_out" 2>/dev/null
      chown 0:0 "$_kl_out" 2>/dev/null
      chcon "$_kl_con" "$_kl_out" 2>/dev/null
      _kl_written=1
    else
      rm -f "$_kl_tmp"
    fi
  done

  rm -f "$_kl_seed"
  [ "$_kl_written" -eq 1 ]
}

is_audio_usb_device() {
  _aud_d=$1
  _aud_dc=$(to_lower "$(cat "$_aud_d/bDeviceClass" 2>/dev/null)")
  [ "$_aud_dc" = "01" ] && return 0

  for _aud_i in "$_aud_d"/*; do
    [ -d "$_aud_i" ] || continue
    _aud_ic=$(to_lower "$(cat "$_aud_i/bInterfaceClass" 2>/dev/null)")
    [ "$_aud_ic" = "01" ] && return 0
    _aud_drv=$(basename "$(readlink "$_aud_i/driver" 2>/dev/null)" 2>/dev/null)
    [ "$_aud_drv" = "snd-usb-audio" ] && return 0
  done
  return 1
}

usb_device_has_hid_interface() {
  _hid_d=$1
  for _hid_i in "$_hid_d"/*; do
    [ -d "$_hid_i" ] || continue
    _hid_cls=$(to_lower "$(cat "$_hid_i/bInterfaceClass" 2>/dev/null)")
    [ "$_hid_cls" = "03" ] && return 0
  done
  return 1
}

usb_device_has_audio_input_name() {
  _hud_d=$1
  for _hud_i in "$_hud_d"/*; do
    [ -d "$_hud_i" ] || continue
    # HID input lives under <iface>/<hid_device>/input/inputN. Some kernels
    # also expose an input symlink directly under the interface, so try both.
    for _hud_hid in "$_hud_i"/input "$_hud_i"/*/input; do
      [ -d "$_hud_hid" ] || continue
      for _hud_inp in "$_hud_hid"/input*; do
        [ -d "$_hud_inp" ] || continue
        _hud_nm=$(to_lower "$(cat "$_hud_inp/name" 2>/dev/null)")
        if is_audio_input_name "$_hud_nm"; then
          return 0
        fi
      done
    done
  done
  return 1
}

generate_usb_input_name_keylayouts() {
  _un_generic=$1
  for _un_d in "$USB_DEVICES_DIR"/*; do
    [ -d "$_un_d" ] || continue
    [ -r "$_un_d/idVendor" ] && [ -r "$_un_d/idProduct" ] || continue
    for _un_i in "$_un_d"/*; do
      [ -d "$_un_i" ] || continue
      for _un_hid in "$_un_i"/input "$_un_i"/*/input; do
        [ -d "$_un_hid" ] || continue
        for _un_inp in "$_un_hid"/input*; do
          [ -d "$_un_inp" ] || continue
          _un_raw=$(cat "$_un_inp/name" 2>/dev/null)
          _un_nm=$(to_lower "$_un_raw")
          if is_audio_input_name "$_un_nm"; then
            _un_can=$(canonical_name "$_un_raw")
            [ -n "$_un_can" ] && write_blocked_kl "$_un_can" "$_un_generic"
          fi
        done
      done
    done
  done
  return 0
}

generate_usb_keylayouts() {
  _gu_generic=$(find_generic_kl) || {
    log_msg "Generic.kl not found; USB keylayouts not generated"
    return 1
  }
  ensure_kl_dir || return 1

  for _gu_d in "$USB_DEVICES_DIR"/*; do
    [ -d "$_gu_d" ] || continue
    [ -r "$_gu_d/idVendor" ] && [ -r "$_gu_d/idProduct" ] || continue

    # Only audio devices that also expose HID can produce button input. A
    # keylayout for an audio-only DAC would just shadow Generic.kl for nothing.
    _gu_gen=0
    if usb_device_has_hid_interface "$_gu_d"; then
      if is_audio_usb_device "$_gu_d" || usb_device_has_audio_input_name "$_gu_d"; then
        _gu_gen=1
      fi
    fi
    [ "$_gu_gen" -eq 1 ] || continue

    _gu_vid=$(to_lower "$(cat "$_gu_d/idVendor" 2>/dev/null)")
    _gu_pid=$(to_lower "$(cat "$_gu_d/idProduct" 2>/dev/null)")
    if is_hex4 "$_gu_vid" && is_hex4 "$_gu_pid" && [ "$_gu_vid" != "0000" ] && [ "$_gu_pid" != "0000" ]; then
      write_blocked_kl "Vendor_${_gu_vid}_Product_${_gu_pid}" "$_gu_generic" ||
        log_msg "failed to write keylayout for $_gu_vid:$_gu_pid"
    fi
  done

  # Name-based fallback for HID-only adapters and devices reporting 0000 IDs.
  generate_usb_input_name_keylayouts "$_gu_generic"
  return 0
}

generate_static_analog_keylayouts() {
  _sa_generic=$(find_generic_kl) || return 1
  ensure_kl_dir || return 1
  for _sa_n in Button_Jack Headset_Jack Wired_Headset; do
    write_blocked_kl "$_sa_n" "$_sa_generic"
  done
  return 0
}

generate_analog_keylayouts() {
  _ga_generic=$(find_generic_kl) || return 1
  ensure_kl_dir || return 1

  # Always mount these so a jack plugged after boot is already covered.
  for _ga_n in Button_Jack Headset_Jack Wired_Headset; do
    write_blocked_kl "$_ga_n" "$_ga_generic"
  done

  [ -r "$INPUT_DEVICES_FILE" ] || return 0
  _ga_bus=""
  while IFS= read -r _ga_line || [ -n "$_ga_line" ]; do
    case "$_ga_line" in
      "I: Bus="*)
        _ga_bus=${_ga_line#I: Bus=}
        _ga_bus=${_ga_bus%% *}
        ;;
      "N: Name="*)
        # Never create a name-based layout for a Bluetooth input device;
        # AVRCP must keep working.
        [ "$_ga_bus" = "0005" ] && continue
        _ga_name=${_ga_line#N: Name=}
        _ga_name=${_ga_name#\"}
        _ga_name=${_ga_name%\"}
        _ga_lname=$(to_lower "$_ga_name")
        case "$_ga_lname" in
          *button*jack*|*headset*jack*|*wired*headset*|*headset*button*)
            _ga_can=$(canonical_name "$_ga_name")
            [ -n "$_ga_can" ] && write_blocked_kl "$_ga_can" "$_ga_generic"
            ;;
        esac
        ;;
    esac
  done < "$INPUT_DEVICES_FILE"
  return 0
}

generate_all_keylayouts() {
  generate_usb_keylayouts
  generate_analog_keylayouts
  return 0
}

unbind_usbhid_for_audio() {
  if [ ! -e "$USBHID_UNBIND_FILE" ]; then
    log_msg "usbhid unbind path unavailable; runtime layer skipped"
    return 1
  fi

  _ub_fail_logged=0
  for _ub_link in "$USBHID_DRIVER_DIR"/*; do
    [ -e "$_ub_link" ] || continue
    _ub_intf=${_ub_link##*/}
    case "$_ub_intf" in
      *:*) ;;
      *) continue ;;
    esac

    _ub_dev=${_ub_intf%%:*}
    _ub_devdir="$USB_DEVICES_DIR/$_ub_dev"
    _ub_intfdir="$USB_DEVICES_DIR/$_ub_intf"
    [ -d "$_ub_devdir" ] || continue
    if [ ! -d "$_ub_intfdir" ]; then
      _ub_intfdir="$_ub_devdir/$_ub_intf"
    fi

    _ub_cls=$(to_lower "$(cat "$_ub_intfdir/bInterfaceClass" 2>/dev/null)")
    [ "$_ub_cls" = "03" ] || continue

    _ub_do=0
    if is_audio_usb_device "$_ub_devdir"; then
      _ub_do=1
    else
      # Covers adapters that expose audio and HID as separate USB devices.
      for _ub_hid in "$_ub_intfdir"/input "$_ub_intfdir"/*/input; do
        [ -d "$_ub_hid" ] || continue
        for _ub_inp in "$_ub_hid"/input*; do
          [ -d "$_ub_inp" ] || continue
          _ub_nm=$(to_lower "$(cat "$_ub_inp/name" 2>/dev/null)")
          if is_audio_input_name "$_ub_nm"; then
            _ub_do=1
            break 2
          fi
        done
      done
    fi
    [ "$_ub_do" -eq 1 ] || continue

    # Do not kill a real boot keyboard/mouse that shares a composite audio
    # device (for example a USB-C dock with audio + keyboard).
    _ub_sub=$(to_lower "$(cat "$_ub_intfdir/bInterfaceSubClass" 2>/dev/null)")
    _ub_proto=$(to_lower "$(cat "$_ub_intfdir/bInterfaceProtocol" 2>/dev/null)")
    case "$_ub_sub:$_ub_proto" in
      01:01|01:02)
        log_msg "keeping boot keyboard/mouse usbhid interface $_ub_intf"
        continue
        ;;
    esac

    if printf '%s\n' "$_ub_intf" > "$USBHID_UNBIND_FILE" 2>/dev/null; then
      log_msg "unbound usbhid interface $_ub_intf"
    else
      if [ "$_ub_fail_logged" -eq 0 ]; then
        log_msg "failed to unbind usbhid interface $_ub_intf (SELinux/read-only?)"
        _ub_fail_logged=1
      fi
    fi
  done
  return 0
}
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/post-fs-data.sh" <<'__USB_BLOCKER_FILE_EOF__'
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
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/service.sh" <<'__USB_BLOCKER_FILE_EOF__'
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
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/hotplug.sh" <<'__USB_BLOCKER_FILE_EOF__'
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
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/META-INF/com/google/android/update-binary" <<'__USB_BLOCKER_FILE_EOF__'
#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v20.4+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ -n "${MAGISK_VER_CODE:-}" ] && [ "$MAGISK_VER_CODE" -lt 20400 ] && require_new_magisk

install_module
exit 0
__USB_BLOCKER_FILE_EOF__

cat > "$BUILD_DIR/META-INF/com/google/android/updater-script" <<'__USB_BLOCKER_FILE_EOF__'
#MAGISK
__USB_BLOCKER_FILE_EOF__

# ---------------------------------------------------------------------------
# Permissoes: scripts executaveis, metadados legiveis.
# ---------------------------------------------------------------------------
chmod 0755 "$BUILD_DIR/customize.sh" \
           "$BUILD_DIR/common.sh" \
           "$BUILD_DIR/post-fs-data.sh" \
           "$BUILD_DIR/service.sh" \
           "$BUILD_DIR/hotplug.sh" \
           "$BUILD_DIR/META-INF/com/google/android/update-binary"
chmod 0644 "$BUILD_DIR/module.prop" \
           "$BUILD_DIR/META-INF/com/google/android/updater-script"

find_python() {
  if [ -n "${PYTHON_BIN:-}" ] && [ -x "${PYTHON_BIN:-}" ]; then
    printf '%s\n' "$PYTHON_BIN"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi
  return 1
}

PY=$(find_python || true)

# ---------------------------------------------------------------------------
# Empacotamento. O zip NAO pode conter a pasta externa.
# ---------------------------------------------------------------------------
rm -f "$OUT"

if [ -n "$PY" ]; then
  printf '%s\n' "- Empacotando com Python (modos Unix preservados)"
  "$PY" - "$BUILD_DIR" "$OUT" <<'PY_ZIP_EOF'
import os
import sys
import zipfile

stage, out = sys.argv[1], sys.argv[2]
files = [
    "module.prop",
    "customize.sh",
    "common.sh",
    "post-fs-data.sh",
    "service.sh",
    "hotplug.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in files:
        path = os.path.join(stage, *name.split("/"))
        if not os.path.isfile(path):
            raise SystemExit("arquivo ausente: " + path)
        zi = zipfile.ZipInfo.from_file(path, name)
        zi.create_system = 3
        mode = 0o755 if (name.endswith(".sh") or name.endswith("update-binary")) else 0o644
        zi.external_attr = (0o100000 | mode) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(path, "rb") as src, z.open(zi, "w") as dst:
            dst.write(src.read())
PY_ZIP_EOF
elif command -v zip >/dev/null 2>&1; then
  printf '%s\n' "- Empacotando com zip"
  ( cd "$BUILD_DIR" && zip -X -r "$OUT" META-INF module.prop customize.sh common.sh post-fs-data.sh service.sh hotplug.sh ) >/dev/null
else
  echo "ERRO: instale zip ou python3 (Termux: pkg install zip python)" >&2
  exit 1
fi

if [ ! -s "$OUT" ]; then
  echo "ERRO: o ZIP nao foi criado: $OUT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Verificacao estrutural (sem depender de unzip).
# ---------------------------------------------------------------------------
if [ -n "$PY" ]; then
  "$PY" - "$OUT" <<'PY_CHECK_EOF'
import sys
import zipfile

required = [
    "module.prop",
    "customize.sh",
    "common.sh",
    "post-fs-data.sh",
    "service.sh",
    "hotplug.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]
with zipfile.ZipFile(sys.argv[1]) as z:
    names = z.namelist()
    missing = [n for n in required if n not in names]
    wrapped = [n for n in names if n.startswith("./") or n.startswith("usb_c_button_blocker/")]
    if missing:
        raise SystemExit("ERRO: entradas ausentes: " + ", ".join(missing))
    if wrapped:
        raise SystemExit("ERRO: caminho com pasta externa no ZIP: " + ", ".join(wrapped))
    print("- ZIP verificado: %d entradas, raiz correta" % len(names))
PY_CHECK_EOF
fi

printf '%s\n' "- Pronto: $OUT"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT"
fi
