#!/system/bin/sh
. ./common_test.sh
PATH=/nonexistent
filter_keys "$PWD/Generic.kl" > "$PWD/filtered.out"