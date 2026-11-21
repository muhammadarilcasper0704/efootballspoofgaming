#!/system/bin/sh
cd "${0%/*}" || exit 1
[ ! -d /data/adb/aril_efo_render_v1 ] || /data/adb/magisk/busybox sh ./performance.sh disable
