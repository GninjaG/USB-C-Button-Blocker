#!/system/bin/sh
MODDIR="$PWD/module"
USB_DEVICES_DIR="$PWD/sys/bus/usb/devices"
USBHID_DRIVER_DIR="$PWD/sys/bus/usb/drivers/usbhid"
USBHID_UNBIND_FILE="$PWD/unbind"
INPUT_DEVICES_FILE="$PWD/input_devices"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
. "$PWD/common_test.sh"
set -x
write_blocked_kl Button_Jack "$KEYLAYOUT_SOURCE"
echo "status=$?"