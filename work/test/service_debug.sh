#!/system/bin/sh
MODDIR="$PWD/service_module"
USB_DEVICES_DIR="$PWD/sys/bus/usb/devices"
USBHID_DRIVER_DIR="$PWD/sys/bus/usb/drivers/usbhid"
USBHID_UNBIND_FILE="$PWD/unbind"
INPUT_DEVICES_FILE="$PWD/input_devices"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
. "$MODDIR/common.sh"
echo "MODDIR=$MODDIR"
echo "KL_DIR=$KL_DIR"
generate_all_keylayouts
echo "gen_status=$?"
find "$MODDIR/system" -type f 2>/dev/null
