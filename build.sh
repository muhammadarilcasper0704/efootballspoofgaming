#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME ke Android NDK}"
mkdir -p deps dist
[ -d deps/zygisk/.git ] || git clone --depth 1 https://github.com/topjohnwu/zygisk-module-sample.git deps/zygisk
[ -d deps/dobby/.git ] || git clone --depth 1 --recursive https://github.com/jmpews/Dobby.git deps/dobby
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
