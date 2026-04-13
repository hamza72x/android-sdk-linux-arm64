# hprof-conv

add_executable(hprof-conv
    ${SRC}/dalvik/tools/hprof-conv/HprofConv.c
    )
target_link_libraries(hprof-conv dl z)
