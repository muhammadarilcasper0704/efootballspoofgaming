#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME ke Android NDK}"
mkdir -p deps dist
[ -d deps/zygisk/.git ] || git clone https://github.com/topjohnwu/zygisk-module-sample.git deps/zygisk
[ -d deps/dobby/.git ] || git clone --recursive https://github.com/jmpews/Dobby.git deps/dobby
git -C deps/dobby checkout --detach 5dfc8546954ce3b3198132ab13fddb89ee92cdd7
git -C deps/zygisk checkout --detach 8ce26128f81baaed0b969aaf7f52f886b61af4ab
# Use an ELF branch relocation for the Android build of the ARM64 bridge.
python3 - <<'PY'
from pathlib import Path
p = Path("deps/dobby/source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.asm")
s = p.read_text()
old = """adrp TMP_REG_0, cdecl(common_closure_bridge_handler)@PAGE
add TMP_REG_0, TMP_REG_0, cdecl(common_closure_bridge_handler)@PAGEOFF
blr TMP_REG_0"""
if old not in s and "bl cdecl(common_closure_bridge_handler)" not in s:
    raise SystemExit("Unexpected upstream assembly")
p.write_text(s.replace(old, "bl cdecl(common_closure_bridge_handler)"))
PY
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static
cmake --build build --target profile
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -a module/. "$stage/"
mkdir -p "$stage/zygisk"
cp build/libprofile.so "$stage/zygisk/arm64-v8a.so"
lib="$stage/zygisk/arm64-v8a.so"
readelf -h "$lib" | grep 'Machine:.*AArch64'
readelf --dyn-syms --wide "$lib" | grep -E 'GLOBAL.*DEFAULT.*zygisk_module_entry$'
if readelf -d "$lib" | grep -E 'libdobby|libc\+\+_shared'; then exit 1; fi
git -C deps/zygisk rev-parse HEAD > "$stage/zygisk-source-revision"
git -C deps/dobby rev-parse HEAD > "$stage/dobby-source-revision"
for dep in dobby zygisk; do
  for license in deps/"$dep"/LICENSE*; do
    [ ! -f "$license" ] || cp "$license" "$stage/$dep-$(basename "$license")"
  done
done
out="$PWD/dist/Aril-eFootball-Personal-arm64.zip"
(cd "$stage" && zip -qr "$stage/output.zip" . -x output.zip)
unzip -tq "$stage/output.zip"
mv "$stage/output.zip" "$out"
