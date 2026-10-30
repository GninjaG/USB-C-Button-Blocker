#!/system/bin/sh
cd "$(dirname "$0")"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
USB_DEVICES_DIR="$PWD/sys/bus/usb/devices"
USBHID_DRIVER_DIR="$PWD/sys/bus/usb/drivers/usbhid"
USBHID_UNBIND_FILE="$PWD/unbind"
INPUT_DEVICES_FILE="$PWD/input_devices"
export KEYLAYOUT_SOURCE USB_DEVICES_DIR USBHID_DRIVER_DIR USBHID_UNBIND_FILE INPUT_DEVICES_FILE
dash "$PWD/job_module/hotplug.sh"
