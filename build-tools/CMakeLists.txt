# build-tools CMakeLists.txt

project(build-tools)
set(EXECUTABLE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/bin/${PROJECT_NAME})

include(aapt.cmake)
include(aapt2.cmake)
include(aidl.cmake)
include(zipalign.cmake)
include(split-select.cmake)
include(dexdump.cmake)
