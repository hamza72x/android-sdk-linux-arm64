# libusb - USB access library (Linux build using AOSP bundled sources)

add_library(libusb STATIC
    ${SRC}/libusb/libusb/core.c
    ${SRC}/libusb/libusb/descriptor.c
    ${SRC}/libusb/libusb/hotplug.c
    ${SRC}/libusb/libusb/io.c
    ${SRC}/libusb/libusb/sync.c
    ${SRC}/libusb/libusb/strerror.c
    ${SRC}/libusb/libusb/os/linux_usbfs.c
    ${SRC}/libusb/libusb/os/events_posix.c
    ${SRC}/libusb/libusb/os/threads_posix.c
    ${SRC}/libusb/libusb/os/linux_netlink.c
    )
target_include_directories(libusb PRIVATE
    ${SRC}/libusb/libusb
    ${SRC}/libusb/libusb/os
    ${SRC}/libusb/linux
    )
target_compile_options(libusb PRIVATE
    -fvisibility=hidden
    -pthread
    )
