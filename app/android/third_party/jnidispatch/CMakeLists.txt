cmake_minimum_required(VERSION 3.18)
project(jnidispatch C ASM)

set(JNA ${JNA_SRC}/native)
set(FFI ${JNA}/libffi)

add_library(ffi STATIC
  ${FFI}/src/prep_cif.c ${FFI}/src/types.c ${FFI}/src/raw_api.c
  ${FFI}/src/java_raw_api.c ${FFI}/src/closures.c ${FFI}/src/tramp.c
  ${FFI}/src/aarch64/ffi.c ${FFI}/src/aarch64/sysv.S)
target_include_directories(ffi PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/cfg ${FFI}/include)
target_compile_definitions(ffi PRIVATE FFI_STATIC_BUILD)
set_target_properties(ffi PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(jnidispatch SHARED ${JNA}/dispatch.c ${JNA}/callback.c)
target_include_directories(jnidispatch PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/hdr ${JNA})
target_compile_definitions(jnidispatch PRIVATE
  _REENTRANT FFI_STATIC_BUILD NO_JAWT NO_WEAK_GLOBALS
  JNA_JNI_VERSION="7.0.2" CHECKSUM="5fb98531302accd485c534c452dd952a")
target_compile_options(jnidispatch PRIVATE
  -O2 -fno-omit-frame-pointer -fno-strict-aliasing -funwind-tables
  -Wno-unused -Wno-parentheses -Wno-int-conversion -Wno-incompatible-pointer-types
  -Wno-implicit-function-declaration)
target_link_libraries(jnidispatch PRIVATE ffi dl log)
target_link_options(jnidispatch PRIVATE -Wl,-Bsymbolic -Wl,--build-id=sha1
  -Wl,-z,max-page-size=16384 -Wl,--gc-sections -s)
