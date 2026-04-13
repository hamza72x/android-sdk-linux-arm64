#
# android-sdk-linux-arm64: Root CMake configuration
#
# Builds Android SDK tools as native Linux ARM64 binaries.
# Adapted from https://github.com/lzhiyong/android-sdk-tools (Apache 2.0)
#

cmake_minimum_required(VERSION 3.14.2)
project(sdk-tools)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)

# Linux native build - use system compiler
find_package(Threads REQUIRED)

# set global cflags and cxxflags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC -Wno-attributes")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -Wno-attributes")

# GCC compatibility: stub out Clang-specific nullability annotations
if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    add_definitions(-D_Nonnull= -D_Nullable= -D_Null_unspecified=)
endif()

# platform tools version
set(TOOLS_VERSION 35.0.2)
set(SRC ${PROJECT_SOURCE_DIR}/src)

# 64-bit off_t for lseek
add_definitions(-D_FILE_OFFSET_BITS=64)

set(PROTOC_COMPILER)

if(DEFINED PROTOC_PATH)
    set(PROTOC_COMPILER ${PROTOC_PATH})

    if(NOT EXISTS ${PROTOC_COMPILER})
        unset(PROTOC_PATH CACHE)
        message(FATAL_ERROR "Invalid protoc: ${PROTOC_COMPILER}, please check if the path is correct")
    endif()

    # check protoc version
    execute_process(
        COMMAND ${PROTOC_COMPILER} --version
        OUTPUT_VARIABLE PTOTOBUF_VERSION
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )

    if(NOT PTOTOBUF_VERSION MATCHES "^libprotoc*")
        unset(PROTOC_PATH CACHE)
        message(FATAL_ERROR "Invalid protoc: ${PROTOC_COMPILER}, this may not be an executable")
    endif()

    string(REGEX MATCH "([0-9]+)\\.([0-9]+)\\.([0-9]+)" VERSIONS ${PTOTOBUF_VERSION})
    if(VERSIONS VERSION_GREATER "3.21.12")
        message(WARNING "${PTOTOBUF_VERSION}, the protobuf version is too high, may be incompatible!!")
    endif()
endif()

# third-party libraries
add_subdirectory(src/boringssl EXCLUDE_FROM_ALL)
add_subdirectory(src/fmtlib EXCLUDE_FROM_ALL)
add_subdirectory(src/pcre EXCLUDE_FROM_ALL)
add_subdirectory(src/libpng EXCLUDE_FROM_ALL)
add_subdirectory(src/zopfli EXCLUDE_FROM_ALL)
add_subdirectory(src/jsoncpp EXCLUDE_FROM_ALL)

# Expat: arc4random_buf detection finds glibc 2.41's implementation but the
# symbol is hidden under -std=c99 compilation. Disable it so expat uses
# getrandom() instead.
set(HAVE_ARC4RANDOM_BUF OFF CACHE BOOL "" FORCE)
set(HAVE_ARC4RANDOM OFF CACHE BOOL "" FORCE)
add_subdirectory(src/expat/expat EXCLUDE_FROM_ALL)
add_subdirectory(src/zstd/build/cmake EXCLUDE_FROM_ALL)
add_subdirectory(src/lz4/build/cmake EXCLUDE_FROM_ALL)
add_subdirectory(src/brotli EXCLUDE_FROM_ALL)
add_subdirectory(src/abseil-cpp EXCLUDE_FROM_ALL)
add_subdirectory(src/protobuf EXCLUDE_FROM_ALL)
add_subdirectory(src/googletest EXCLUDE_FROM_ALL)
add_subdirectory(src/tinyxml2 EXCLUDE_FROM_ALL)

# building sdk-tools
add_subdirectory(lib)
add_subdirectory(build-tools)
add_subdirectory(platform-tools)
add_subdirectory(others)
