#!/system/bin/sh
ui_print() { echo "UI: $1"; }
abort() { echo "ABORT: $1" >&2; exit 1; }
set_perm_recursive() { :; }
set_perm() { :; }
MODPATH="$PWD/install_module"
MODDIR="$MODPATH"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
export MODPATH MODDIR KEYLAYOUT_SOURCE
. "$MODPATH/customize.sh"
