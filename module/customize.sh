[ "$ARCH" = arm64 ] || abort "Paket ini khusus ARM64."
[ -s "$MODPATH/zygisk/arm64-v8a.so" ] || abort "Komponen native tidak ada."
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/ctl.sh" 0 0 0755
if [ -d /data/adb/aril_efo_render_v1 ]; then
  abort "Buka WebUI versi lama, tekan Pulihkan profil performa, lalu pasang ZIP ini kembali."
fi
# Retain valid profile choices when upgrading the same module.
for item in selection previous; do
  old="/data/adb/modules/aril_efo_personal/$item"
  if [ -f "$old" ]; then
    bits=$(cat "$old")
    case "$bits" in
      [01][01][01]) printf '%s\n' "$bits" > "$MODPATH/$item" || abort "Gagal memulihkan $item."
                    set_perm "$MODPATH/$item" 0 0 0600 ;;
    esac
  fi
done
if [ ! -f "$MODPATH/selection" ]; then
  printf '111\n' > "$MODPATH/selection" || abort "Gagal mengaktifkan profil iPhone 6."
  set_perm "$MODPATH/selection" 0 0 0600
fi
ui_print "Aktifkan Zygisk dan reboot. Buka WebUI untuk memilih profil."
