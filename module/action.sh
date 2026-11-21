#!/system/bin/sh
if pm path io.github.a13e300.ksuwebui | grep -q '^package:'; then
  exec am start -n io.github.a13e300.ksuwebui/.WebUIActivity -e id aril_efo_personal
fi
echo "Pasang KsuWebUIStandalone, beri akses root, lalu tekan Aksi lagi."
