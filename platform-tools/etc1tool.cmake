# etc1tool - ETC1 texture tool (Linux build)

add_executable(etc1tool
    ${SRC}/development/tools/etc1tool/etc1tool.cpp
    ${SRC}/native/opengl/libs/ETC1/etc1.cpp
    )
target_include_directories(etc1tool PRIVATE
    ${SRC}/libpng
    ${SRC}/native/opengl/include
    )
target_link_libraries(etc1tool png_static dl z)
