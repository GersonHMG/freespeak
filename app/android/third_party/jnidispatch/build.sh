#!/usr/bin/env bash
# Rebuilds app/src/main/jniLibs/arm64-v8a/libjnidispatch.so from JNA 5.15.0
# with a current NDK. See README.md for why. Run from Git Bash or Linux.
set -euo pipefail
cd "$(dirname "$0")"
NDK="${ANDROID_NDK:-$LOCALAPPDATA/Android/Sdk/ndk/28.2.13676358}"
WORK="${TMPDIR:-/tmp}/jnidispatch-build"
mkdir -p "$WORK"
if [ ! -d "$WORK/jna-5.15.0" ]; then
  curl -sL https://github.com/java-native-access/jna/archive/refs/tags/5.15.0.tar.gz | tar xz -C "$WORK"
fi
cmake -S . -B "$WORK/out" -G Ninja \
  -DJNA_SRC="$WORK/jna-5.15.0" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/out"
cp "$WORK/out/libjnidispatch.so" ../../app/src/main/jniLibs/arm64-v8a/
