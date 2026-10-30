#!/system/bin/sh
MODDIR="$PWD/fix_module"
. "$PWD/common_test.sh"
fix_system_tree_contexts
echo status=$?
