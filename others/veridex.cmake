# veridex - Hidden API usage checker (Linux build)

add_executable(veridex
    ${SRC}/art/tools/veridex/flow_analysis.cc
    ${SRC}/art/tools/veridex/hidden_api.cc
    ${SRC}/art/tools/veridex/hidden_api_finder.cc
    ${SRC}/art/tools/veridex/precise_hidden_api_finder.cc
    ${SRC}/art/tools/veridex/resolver.cc
    ${SRC}/art/tools/veridex/veridex.cc
    )

target_include_directories(veridex PRIVATE
    ${SRC}/art/libdexfile
    ${SRC}/art/libartbase
    ${SRC}/art/libartpalette/include
    ${SRC}/extras/module_ndk_libs/libnativehelper/include_jni
    ${SRC}/fmtlib/include
    ${SRC}/logging/liblog/include
    ${SRC}/libbase/include
    ${SRC}/libziparchive/include
    )

target_compile_definitions(veridex PRIVATE
    ART_STACK_OVERFLOW_GAP_arm=8192
    ART_STACK_OVERFLOW_GAP_arm64=8192
    ART_STACK_OVERFLOW_GAP_riscv64=8192
    ART_STACK_OVERFLOW_GAP_x86=8192
    ART_STACK_OVERFLOW_GAP_x86_64=8192
    ART_FRAME_SIZE_LIMIT=1736
    )

target_link_libraries(veridex
    libdexfile
    libartbase
    libartpalette
    libbase
    liblog
    libziparchive
    fmt::fmt
    Threads::Threads
    dl
    z
    )
