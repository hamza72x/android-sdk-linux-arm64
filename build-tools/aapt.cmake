# aapt - Android Asset Packaging Tool (legacy, Linux build)

set(INCLUDES
    ${SRC}/base/libs/androidfw/include
    ${SRC}/base/libs/androidfw/include_pathutils
    ${SRC}/expat/lib
    ${SRC}/fmtlib/include
    ${SRC}/libpng
    ${SRC}/libbase/include
    ${SRC}/native/include
    ${SRC}/core/libutils/include
    ${SRC}/core/libsystem/include
    ${SRC}/logging/liblog/include
    ${SRC}/soong/cc/libbuildversion/include
    ${SRC}/incremental_delivery/incfs/util/include
    ${SRC}/incremental_delivery/incfs/kernel-headers
    )

add_library(libaapt STATIC
    ${SRC}/base/tools/aapt/AaptAssets.cpp
    ${SRC}/base/tools/aapt/AaptConfig.cpp
    ${SRC}/base/tools/aapt/AaptUtil.cpp
    ${SRC}/base/tools/aapt/AaptXml.cpp
    ${SRC}/base/tools/aapt/ApkBuilder.cpp
    ${SRC}/base/tools/aapt/Command.cpp
    ${SRC}/base/tools/aapt/CrunchCache.cpp
    ${SRC}/base/tools/aapt/FileFinder.cpp
    ${SRC}/base/tools/aapt/Images.cpp
    ${SRC}/base/tools/aapt/Package.cpp
    ${SRC}/base/tools/aapt/pseudolocalize.cpp
    ${SRC}/base/tools/aapt/Resource.cpp
    ${SRC}/base/tools/aapt/ResourceFilter.cpp
    ${SRC}/base/tools/aapt/ResourceIdCache.cpp
    ${SRC}/base/tools/aapt/ResourceTable.cpp
    ${SRC}/base/tools/aapt/SourcePos.cpp
    ${SRC}/base/tools/aapt/StringPool.cpp
    ${SRC}/base/tools/aapt/Utils.cpp
    ${SRC}/base/tools/aapt/WorkQueue.cpp
    ${SRC}/base/tools/aapt/XMLNode.cpp
    ${SRC}/base/tools/aapt/ZipEntry.cpp
    ${SRC}/base/tools/aapt/ZipFile.cpp
    )
target_compile_definitions(libaapt PRIVATE
    -DSTATIC_ANDROIDFW_FOR_TOOLS
    )
target_include_directories(libaapt PRIVATE ${INCLUDES})

add_executable(aapt ${SRC}/base/tools/aapt/Main.cpp)
target_compile_definitions(aapt PRIVATE
    -DSTATIC_ANDROIDFW_FOR_TOOLS
    )
target_include_directories(aapt PRIVATE ${INCLUDES})
target_link_libraries(aapt
    libaapt
    libandroidfw
    libincfs
    libutils
    libcutils
    libselinux
    libsepol
    libziparchive
    libpackagelistparser
    libbase
    libbuildversion
    libprocessgroup
    liblog
    expat
    crypto
    pcre2-8
    jsoncpp_static
    png_static
    Threads::Threads
    dl
    z
    )
