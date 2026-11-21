#!/system/bin/sh
set -eu
cd "${0%/*}"
umask 077
case "${1:-}" in before|after) label=$1;; *) exit 2;; esac
sleep 5
pid=$(pidof jp.konami.pesam | cut -d' ' -f1)
[ -n "$pid" ] || { echo "Game belum berjalan." >&2; exit 1; }
layer=$(dumpsys SurfaceFlinger --list | awk '/SurfaceView/ && /jp\.konami\.pesam/ && /BLAST/ {if($0 !~ /Background|Bounds|InputSink/){print;exit}}')
[ -n "$layer" ] || { echo "SurfaceView eFootball tidak ditemukan. Kembali ke pertandingan saat pengukuran." >&2;exit 1; }
last=$(dumpsys SurfaceFlinger --latency "$layer" | awk 'NF==3 && $2~/^[1-9][0-9]*$/ && $2!="9223372036854775807" && $2+0>t {t=$2} END{printf "%.0f",t}')
[ "$last" != 0 ] || { echo "Belum ada frame awal. Pilih adegan yang bergerak." >&2; exit 1; }
sleep 2
raw=$(dumpsys SurfaceFlinger --latency "$layer")
[ "$(pidof jp.konami.pesam | cut -d' ' -f1)" = "$pid" ] || { echo "PID berubah. Ulangi.";exit 1; }
summary=$(printf '%s\n' "$raw" | awk -v cut="$last" '
NF==3 && $2~/^[1-9][0-9]*$/ && $2!="9223372036854775807" && $2+0>cut+0 {
  t=$2+0;if(prev && t>prev){d=(t-prev)/1000000;a[++n]=d;sum+=d}if(t>prev)prev=t
}END{if(n<10)exit 1;for(i=2;i<=n;i++){x=a[i];j=i-1;while(j>0&&a[j]>x){a[j+1]=a[j];j--}a[j+1]=x}
 printf "%d interval | %.1f FPS tampil | P95 %.1f ms",n,1000*n/sum,a[int((95*n+99)/100)]}') || { echo "Data frame baru kurang dari 10 interval. Ulangi saat latihan berjalan." >&2;exit 1; }
tmp=$(mktemp "./frame.XXXXXX");trap 'rm -f "$tmp"' EXIT
printf '%s — %s\n' "$(date '+%H:%M:%S')" "$summary" > "$tmp";mv "$tmp" "frame.$label"
echo "$summary"
