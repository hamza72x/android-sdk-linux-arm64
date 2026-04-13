# zipalign - APK alignment tool (Linux build)

add_executable(zipalign
    ${SRC}/build/tools/zipalign/ZipAlign.cpp
    ${SRC}/build/tools/zipalign/ZipEntry.cpp
    ${SRC}/build/tools/zipalign/ZipFile.cpp
    ${SRC}/build/tools/zipalign/ZipAlignMain.cpp
    )

target_include_directories(zipalign PRIVATE
    ${SRC}/build/tools/zipalign/include
    ${SRC}/core/libutils/include
    ${SRC}/logging/liblog/include
    ${SRC}/zopfli/src
    ${SRC}/libbase/include
    ${SRC}/libziparchive/include
    )

target_link_libraries(zipalign
    libutils
    libbase
    libziparchive
    libzopfli
    liblog
    Threads::Threads
    dl
    z
    )
