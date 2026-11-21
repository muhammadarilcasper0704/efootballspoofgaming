# Aril eFootball Personal

Proyek modul Magisk/Zygisk ARM64 untuk proses utama jp.konami.pesam. Profil awal 000, seluruh pilihan mati. Mesin profil ditulis untuk proyek ini. Dependensi build meliputi Android NDK, header publik Zygisk, dan Dobby untuk intersepsi satu fungsi GLES.

## Membuat ZIP instalasi

Ekstrak arsip proyek. Di repositori GitHub pribadimu, letakkan isinya di root termasuk .github/workflows/build.yml. Buka Actions → Build Aril eFootball. Setelah build hijau, unduh artefak Aril-eFootball-Magisk, ekstrak sekali dan ambil Aril-eFootball-Personal-arm64.zip. Alternatif di Linux dengan git, cmake, ninja, binutils, zip, unzip dan NDK r27c, jalankan ANDROID_NDK_HOME=/path/ke/ndk bash build.sh. Build mengambil sumber dependensi dari GitHub. Revisi yang dipakai dicatat di dalam ZIP hasil build.

## Menggunakan di ROG Phone 5

Jika profil COPG sebelumnya aktif untuk eFootball, pulihkan dahulu lewat panel lama agar hasil uji bisa diatribusikan ke modul ini. Pasang ZIP hasil build melalui Magisk, aktifkan Zygisk, lalu reboot. Buka WebUI Aril • eFootball Personal. Pilih satu fitur, terapkan, paksa berhenti game dan buka kembali. Periksa status saat game berjalan. Ulangi untuk fitur berikutnya. Untuk kembali ke setelan asli, pilih Nonaktifkan semua dan mulai ulang game. Jika game gagal diluncurkan, panel dapat digunakan saat game tertutup.

## Cakupan

- Device mengisi field Java android.os.Build lalu membaca nilainya kembali. Jalur pembacaan properti native, versi Android dan ABI berada di luar cakupan.
- CPU mencoba memasang berkas cpuinfo sintetis dalam mount namespace privat proses lalu memeriksanya lagi setelah spesialisasi. Keberhasilan bergantung pada namespace dan kebijakan SELinux di ROM. Jumlah CPU scheduler dan fitur instruksi tetap berasal dari perangkat.
- GPU mengubah GL_VENDOR dan GL_RENDERER pada ekspor glGetString dari libGLESv2.so. Profil GPU mewakili Mali-T720 MP2 dengan renderer Mali-T720. Log membedakan antara pemasangan dan kueri renderer yang benar-benar teramati. Vulkan serta jalur dispatch lain belum didukung.
- Status membaca log dengan PID proses utama. Jika log kosong, jalur eksekusi belum terbukti. Backup memulihkan pilihan sebelum perubahan terakhir. Dalam kasus data terputus, konfigurasi aktif selalu berasal dari satu berkas yang diganti dengan rename.
- Validasi host mencakup parser pilihan, struktur paket sumber, pemeriksaan sintaks shell dan JavaScript. Kompilasi NDK dan pengujian pada ROG Phone 5 diperlukan untuk menilai kompatibilitas dan frame time.
