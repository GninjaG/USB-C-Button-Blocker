MODDIR="$PWD/module"
USB_DEVICES_DIR="$PWD/sys/bus/usb/devices"
USBHID_DRIVER_DIR="$PWD/sys/bus/usb/drivers/usbhid"
USBHID_UNBIND_FILE="$PWD/unbind"
INPUT_DEVICES_FILE="$PWD/input_devices"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
export MODDIR USB_DEVICES_DIR USBHID_DRIVER_DIR USBHID_UNBIND_FILE INPUT_DEVICES_FILE KEYLAYOUT_SOURCE
. "$PWD/common_test.sh"
generate_all_keylayouts
echo "GEN_EXIT=$?"
unbind_usbhid_for_audio
echo "UNBIND_EXIT=$?"
