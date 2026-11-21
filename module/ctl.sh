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
status)
  read_current
  echo "Pilihan perangkat/CPU/GPU: $current (1 = aktif)"
  pid=$(pidof jp.konami.pesam 2>/dev/null | cut -d' ' -f1)
  if [ -n "$pid" ]; then
    echo "PID eFootball: $pid"
    logcat -d -t 3000 --pid="$pid" -s 'ArilEFO:I' '*:S' | tail -12
  else echo "Game belum berjalan."; fi
  ;;
set|restore)
  # Magisk BusyBox releases the advisory lock when this process exits.
  exec 9>selection.lock
  /data/adb/magisk/busybox flock -n 9 || { echo "Panel sedang digunakan atau flock tidak tersedia." >&2; exit 1; }
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
