#!/system/bin/sh
set -eu
cd "${0%/*}"
umask 077
valid() { case "$1" in [01][01][01]) return 0;; *) return 1;; esac; }
read_current() {
  if [ -f selection ]; then current=$(cat selection); else current=000; fi
  valid "$current" || { echo "Konfigurasi tidak valid." >&2; exit 1; }
}
case "${1:-}" in
boost|unboost)
  if [ "$1" = boost ]; then op=enable; else op=disable; fi
  exec /data/adb/magisk/busybox sh ./performance.sh "$op";;
before|after) exec /data/adb/magisk/busybox sh ./measure.sh "$1";;
status)
  read_current
  echo "Pilihan perangkat/CPU/GPU: $current (1 = aktif)"
  pid=$(pidof jp.konami.pesam 2>/dev/null | cut -d' ' -f1)
  if [ -n "$pid" ]; then
    echo "PID eFootball: $pid"
    if [ -r "/proc/$pid/root/proc/cpuinfo" ]; then
      if cmp -s cpuinfo "/proc/$pid/root/proc/cpuinfo"; then echo "CPU: cpuinfo PID cocok persis dengan profil 4 inti."; else rc=$?; if [ "$rc" -eq 1 ]; then echo "CPU: cpuinfo PID berbeda dari profil."; else echo "CPU: pembandingan cpuinfo gagal."; fi; fi
    else echo "CPU: cpuinfo PID tidak bisa dibaca."; fi
    # Drop records from earlier processes which used the same PID.
    ticks=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}')
    hz=$(getconf CLK_TCK 2>/dev/null || :)
    uptime=$(cut -d' ' -f1 /proc/uptime)
    since=$(awk -v now="$(date +%s)" -v u="$uptime" -v t="$ticks" -v hz="$hz" 'BEGIN{if(t+0>0 && hz+0>0)printf "%.0f",now-u+t/hz-2}')
    logs=''
    if [ -n "$since" ]; then
      logs=$(logcat -d -v epoch --pid="$pid" -s 'ArilEFO:I' '*:S' 2>/dev/null | awk -v s="$since" '$1+0>=s' | tail -25)
    fi
    printf '%s\n' "$logs"
    case "$logs" in *"field Java Build terbaca kembali"*) echo "Device: modul memverifikasi Java Build di proses. Pembacaan oleh kode game belum diukur.";; *) echo "Device: verifikasi Java Build belum terlihat.";; esac
    case "$logs" in *"mengembalikan Mali-T720"*) echo "GPU: kueri GL_RENDERER teramati di proses.";; *) echo "GPU: belum ada bukti kueri renderer OpenGL ES.";; esac
    case "$logs" in *"kueri ekstensi teramati"*) echo "Ekstensi GLES: jumlah token teramati pada log di atas.";; *) echo "Ekstensi GLES: belum ada bukti enumerasi."; esac
  else echo "Game belum berjalan."; fi
  /data/adb/magisk/busybox sh ./performance.sh status
  for key in before after; do
    if [ -r "frame.$key" ]; then printf '%s: ' "$key";cat "frame.$key";fi
  done
  ;;
set|restore)
  # flock opens the path and holds the lock for the entire child command.
  busybox=/data/adb/magisk/busybox
  [ -x "$busybox" ] || { echo "Magisk BusyBox tidak ditemukan." >&2; exit 1; }
  exec "$busybox" flock -x selection.lock "$busybox" sh ./ctl.sh locked "$@"
  ;;
locked)
  shift
  case "${1:-}" in set|restore) ;; *) exit 2;; esac
  read_current
  if [ "$1" = restore ]; then
    [ -f previous ] || { echo "Belum ada backup." >&2; exit 1; }
    next=$(cat previous)
  else next=${2:-}; fi
  valid "$next" || exit 2
  [ "$current" != "$next" ] || { echo "Pilihan sudah sesuai."; exit 0; }
  trap 'rm -f selection.new previous.new' EXIT
  if [ "$1" = set ]; then
    printf '%s\n' "$current" > previous.new && mv -f previous.new previous
  fi
  printf '%s\n' "$next" > selection.new && mv -f selection.new selection
  echo "Pilihan tersimpan: $next. Paksa berhenti lalu buka lagi game."
  ;;
*) exit 2;;
esac
