#!/system/bin/sh
ui_print() { echo "UI: $1"; }
abort() { echo "ABORT: $1" >&2; exit 1; }
set_perm_recursive() { :; }
set_perm() { :; }
MODPATH="$PWD/install_final"
KEYLAYOUT_SOURCE="$PWD/Generic.kl"
export MODPATH KEYLAYOUT_SOURCE
. "$MODPATH/customize.sh"
