#!/system/bin/sh
MODDIR="$PWD/fix_module"
. "$PWD/common_fix_test.sh"
fix_system_tree_contexts
echo "status=$?"
