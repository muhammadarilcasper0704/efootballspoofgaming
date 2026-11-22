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
  echo "Pilihan perangkat/CPU/GPU: $current (pilihan tersimpan)"
  pid=$(pidof jp.konami.pesam 2>/dev/null | cut -d' ' -f1)
  if [ -n "$pid" ]; then
    echo "PID eFootball: $pid"
    # Match only the descriptor owned by the live game process. The kernel
    # discards it on process exit, so recycled PIDs cannot inherit evidence.
    stamp=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}')
    fdnum=$(ls -l "/proc/$pid/fd" 2>/dev/null | awk '$NF=="(deleted)" && $(NF-1)=="/memfd:aril-efo-062" && $(NF-2)=="->" && $(NF-3)~/^[0-9]+$/ {print $(NF-3);exit}')
    fd=${fdnum:+/proc/$pid/fd/$fdnum}
    record=''
    if [ -n "$fd" ]; then record=$(dd if="$fd" bs=10 count=1 2>/dev/null || :); fi
    again=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}')
    [ -n "$stamp" ] && [ "$stamp" = "$again" ] || { echo "PID berubah. Periksa kembali."; exit 0; }
    case "$record" in
      [01][01][01][01-][01-][01-][01-][01-][01-][01-])
        active=$(printf '%s' "$record" | cut -c1-3)
        echo "Modul 0.6.2 dimuat di PID ini dengan pilihan $active."
        [ "$active" = "$current" ] || echo "Pilihan baru berlaku setelah game dibuka ulang."
        show() {
          value=$(printf '%s' "$record" | cut -c"$1")
          case "$value" in 1) echo "$2: terverifikasi.";; 0) echo "$2: gagal.";; *) echo "$2: belum teramati atau tidak dipilih.";; esac
        }
        show 4 "Perangkat iPhone 6 (Java Build)"
        show 5 "CPU Apple A8 (dibaca oleh modul setelah proses siap)"
        show 6 "Pemasangan hook GLES"
        show 7 "Kueri GL_RENDERER mengembalikan Apple A8 GPU"
        show 8 "Kueri ekstensi GLES"
        show 9 "Uji baca CPU melalui libc (jalur cadangan)"
        show 10 "Proses membuka profil CPU melalui libc di luar uji modul"
        ;;
      *) echo "Catatan proses tidak ditemukan atau tidak dapat dibaca. Periksa modul dan Zygisk di Magisk, reboot setelah pembaruan, lalu buka ulang eFootball.";;
    esac
    if [ -r "/proc/$pid/root/proc/cpuinfo" ]; then
      if cmp -s cpuinfo "/proc/$pid/root/proc/cpuinfo"; then echo "CPU: cpuinfo PID cocok persis dengan profil 2 inti Typhoon."; else rc=$?; if [ "$rc" -eq 1 ]; then echo "CPU: pembacaan kernel berbeda. Lihat hasil uji libc di atas."; else echo "CPU: pembandingan cpuinfo gagal."; fi; fi
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
  else echo "Game belum berjalan."; fi
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
