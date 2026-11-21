[ "$ARCH" = arm64 ] || abort "Paket ini khusus ARM64."
[ -s "$MODPATH/zygisk/arm64-v8a.so" ] || abort "Komponen native tidak ada."
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/ctl.sh" 0 0 0755
ui_print "Aktifkan Zygisk dan reboot. Buka WebUI untuk memilih profil."
