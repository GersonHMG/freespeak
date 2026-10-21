cmake_minimum_required(VERSION 3.18)
project(espeak_ng C)

set(ESPEAK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/espeak-ng")

# Support both older (speak_lib.c) and newer (speech.c) espeak-ng layout
if(NOT EXISTS "${ESPEAK_ROOT}/src/libespeak-ng/speech.c" AND NOT EXISTS "${ESPEAK_ROOT}/src/libespeak-ng/speak_lib.c")
  message(FATAL_ERROR
    "espeak-ng source not found at ${ESPEAK_ROOT}. "
    "Run scripts/setup_espeak.sh first.")
endif()

set(ESPEAK_SRC_DIR "${ESPEAK_ROOT}/src/libespeak-ng")
file(GLOB ESPEAK_SOURCES "${ESPEAK_SRC_DIR}/*.c")
# Exclude speechPlayer sources when USE_SPEECHPLAYER is 0 (no speechPlayer.h in build)
list(FILTER ESPEAK_SOURCES EXCLUDE REGEX "sPlayer\\.c$")

# UCD tools for Unicode character classification
file(GLOB UCD_SOURCES
  "${ESPEAK_ROOT}/src/ucd-tools/src/*.c"
)

add_library(espeak-ng SHARED ${ESPEAK_SOURCES} ${UCD_SOURCES})

target_include_directories(espeak-ng PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${ESPEAK_ROOT}/src/include"
  "${ESPEAK_ROOT}/src/include/espeak-ng"
  "${ESPEAK_ROOT}/src/libespeak-ng"
  "${ESPEAK_ROOT}/src/ucd-tools/src/include"
)

target_compile_definitions(espeak-ng PRIVATE
  HAVE_STDINT_H=1
  PACKAGE_VERSION="1.52.0"
  DATA_FROM_FILE=1
)

target_compile_options(espeak-ng PRIVATE -w)
