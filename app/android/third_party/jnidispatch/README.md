# libjnidispatch.so (JNA 5.15.0, rebuilt with NDK r28)

vosk_flutter_service pulls in `net.java.dev.jna:jna:5.15.0`. Every published
JNA aar up to at least 5.19.1 ships an arm64 `libjnidispatch.so` built with
GCC 4.9 from a pre-r18 NDK. Play flags it: "compiled using an older Android
NDK version that can still cause crashes" on 16 KB devices. In that build the
GNU_RELRO segment ends 4 KB-aligned inside the RW segment, so rounding it to
16 KB on a 16 KB device would make `.data`/`.bss` read-only. Newer JNA
releases only change `max-page-size`, so upgrading JNA does not fix it.

This folder rebuilds the same native library (JNA tag 5.15.0, libffi 3.4.4)
with NDK r28. The app ships the result from
`app/src/main/jniLibs/arm64-v8a/`, and `app/build.gradle.kts` uses
`pickFirsts` so it wins over the copy in the JNA aar.

- `cfg/`: hand-written `fficonfig.h` and generated `ffi.h` for
  aarch64-linux-android, matching what libffi's configure would produce.
- `hdr/`: JNI headers from `javac -h` on JNA 5.15.0's `Native.java` and
  `Function.java`.
- The `JNA_JNI_VERSION` ("7.0.2") and `CHECKSUM` defines in `CMakeLists.txt`
  must match what JNA's Java side expects. They are read from the original
  5.15.0 library. If the JNA version changes, regenerate `hdr/`, update both
  defines and the tag in `build.sh`.

Rebuild with `bash build.sh` (Git Bash, with CMake and Ninja on PATH).
Only arm64-v8a is rebuilt, because release builds ship only that ABI.
