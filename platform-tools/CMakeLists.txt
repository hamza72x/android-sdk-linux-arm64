# platform-tools CMakeLists.txt

project(platform-tools)
set(EXECUTABLE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/bin/${PROJECT_NAME})

include(hprof-conv.cmake)
include(sqlite3.cmake)
include(etc1tool.cmake)
include(e2fsprogs.cmake)
include(f2fs-tools.cmake)
include(fastboot.cmake)
include(adb.cmake)
