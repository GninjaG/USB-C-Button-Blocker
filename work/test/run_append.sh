#!/system/bin/sh
MODDIR="$PWD/module"
USB_DEVICES_DIR="$PWD/sys/bus/usb/devices"
USBHID_DRIVER_DIR="$PWD/sys/bus/usb/drivers/usbhid"
USBHID_UNBIND_FILE="$PWD/unbind_append"
INPUT_DEVICES_FILE="$PWD/input_devices"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
. "$PWD/common_append.sh"
: > "$USBHID_UNBIND_FILE"
unbind_usbhid_for_audio
echo "UNBIND_EXIT=$?"