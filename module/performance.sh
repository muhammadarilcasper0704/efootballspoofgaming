#!/system/bin/sh
# Runs under Magisk's BusyBox ash.
set -eu
cd "${0%/*}"
umask 077
pkg=jp.konami.pesam
bb=/data/adb/magisk/busybox
state=/data/adb/aril_efo_render_v1
game_list=/data/system/game_mode_intervention.list
fail() { echo "$*" >&2; exit 1; }
get_overlay() { device_config get game_overlay "$pkg"; }
mode_now() {
  [ -r "$game_list" ] || return 0
  awk -v pkg="$pkg" -v uid="$uid" '$1==pkg && $2==uid && $3~/^[123]$/ {print $3;exit}' "$game_list"
}
overlay_for() {
  printf '%s\n' "$1" | awk '
  {n=split($0, rows, ":"); out=""; count=0;
   for(i=1;i<=n;i++){r=rows[i]; if(r=="null"||r=="")continue;
     if(r~/(^|,)mode=2(,|$)/){count++; k=split(r,f,","); r="";
       for(j=1;j<=k;j++)if(f[j]!~/^(downscaleFactor|fps)=/)r=r (r?",":"") f[j];
       r=r ",downscaleFactor=0.7,fps=0";
     } out=out (out?":":"") r
   } if(count>1)exit 2;
   if(!count)out=out (out?":":"") "mode=2,downscaleFactor=0.7,fps=0";
   print out}'
}
set_mode() {
  case "$1" in 1) name=standard;; 2) name=performance;; 3) name=battery;; *) return 1;; esac
  cmd game mode --user "$user" "$name" "$pkg"
}
restore() {
  [ -d "$state" ] || { echo "Tidak ada profil performa untuk dipulihkan."; return 0; }
  old=$(cat "$state/overlay"); target=$(cat "$state/target"); mode=$(cat "$state/mode")
  user=$(cat "$state/user"); uid=$(cat "$state/uid")
  current=$(get_overlay)
  [ "$current" = "$target" ] || [ "$current" = "$old" ] || fail "Overlay telah berubah di luar modul. Backup dipertahankan."
  now=$(mode_now)
  if [ "$mode" != manual ] && [ "$mode" != 2 ] && { [ "$now" = 2 ] || [ -z "$now" ]; }; then
    set_mode "$mode" || fail "Pemulihan mode gagal. Backup masih ada."
  fi
  if [ "$current" != "$old" ]; then
    if [ "$old" = null ]; then device_config delete game_overlay "$pkg"; else device_config put game_overlay "$pkg" "$old"; fi
  fi
  [ "$(get_overlay)" = "$old" ] || fail "Pemulihan overlay belum terverifikasi."
  rm -rf "$state"
  echo "Overlay sebelumnya dipulihkan. Buka ulang eFootball."
}
case "${1:-}" in
enable|disable)
  exec "$bb" flock -x /data/adb/aril_efo_render.lock "$bb" sh ./performance.sh locked "$1";;
locked)
  if [ "$2" = disable ]; then restore; exit; fi
  [ "$2" = enable ] || exit 2
  user=$(am get-current-user)
  case "$user" in ''|*[!0-9]*) fail "Profil pengguna Android tidak terbaca.";; esac
  uid=$(cmd package list packages -U --user "$user" "$pkg" | awk -v p="package:$pkg" '$1==p && $2~/^uid:[0-9]+$/ {sub(/^uid:/,"",$2);print $2;exit}')
  [ -n "$uid" ] || fail "Paket game tidak ditemukan untuk pengguna aktif."
  if [ -d "$state" ]; then
    [ "$(get_overlay)" = "$(cat "$state/target")" ] || fail "Profil pernah diterapkan. Pulihkan dulu sebelum mencoba lagi."
    echo "Overlay 70% sudah tersimpan. Periksa audit untuk mode Android yang aktif.";exit
  fi
  old=$(get_overlay)
  case "$old" in null|mode=*) ;; *) fail "Format overlay OEM belum dikenali.";; esac
  target=$(overlay_for "$old") || fail "Konfigurasi mode Performance ambigu."
  mode=$(mode_now); mode=${mode:-manual}
  tmp=$(mktemp -d /data/adb/aril_efo_new.XXXXXX); trap 'rmdir "$tmp" 2>/dev/null || :' EXIT
  for key in overlay target mode user uid; do
    case "$key" in overlay)v=$old;;target)v=$target;;mode)v=$mode;;user)v=$user;;uid)v=$uid;;esac
    printf '%s\n' "$v" > "$tmp/$key"
  done
  mv "$tmp" "$state"
  device_config put game_overlay "$pkg" "$target" && [ "$(get_overlay)" = "$target" ] || fail "Overlay gagal disimpan. Gunakan Pulihkan."
  if [ "$mode" = manual ]; then echo "Overlay tersimpan. Mode awal tidak terbaca; pilih Performance di pengaturan game Android jika tersedia."
  else set_mode 2 || fail "Android menolak mode Performance. Gunakan Pulihkan."; fi
  echo "Skala 70% diminta. Paksa berhenti lalu buka kembali game.";;
status)
  if [ ! -d "$state" ]; then echo "Profil render: belum diterapkan.";exit;fi
  current=$(get_overlay); [ "$current" = "$(cat "$state/target")" ] && echo "Overlay 70% tersimpan." || echo "Overlay berbeda dari profil modul."
  uid=$(cat "$state/uid"); mode=$(mode_now)
  echo "Mode Android: ${mode:-belum teramati} (2 = Performance)."
  if [ -r "$game_list" ]; then awk -v p="$pkg" -v u="$uid" '$1==p && $2==u{for(i=4;i<NF;i+=2)if($i==2)print "Intervensi Performance menurut Android: " $(i+1)}' "$game_list"; fi
  echo "Ukuran buffer aktual belum diukur.";;
*) exit 2;;
esac
