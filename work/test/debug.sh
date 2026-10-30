#!/system/bin/sh
MODDIR="$PWD/module"
USB_DEVICES_DIR="$PWD/sys/bus/usb/devices"
USBHID_DRIVER_DIR="$PWD/sys/bus/usb/drivers/usbhid"
USBHID_UNBIND_FILE="$PWD/unbind"
INPUT_DEVICES_FILE="$PWD/input_devices"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
. "$PWD/common_test.sh"
echo "writable=$([ -w "$USBHID_UNBIND_FILE" ] && echo yes || echo no)"
echo "driver entries:"; ls -la "$USBHID_DRIVER_DIR"
for l in "$USBHID_DRIVER_DIR"/*; do echo "link=$l basename=${l##*/}"; done
set -x
unbind_usbhid_for_audio
set +x
echo "after: $(cat "$USBHID_UNBIND_FILE")"