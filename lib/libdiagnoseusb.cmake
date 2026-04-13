# libdiagnoseusb

add_library(libdiagnoseusb STATIC
    ${SRC}/core/diagnose_usb/diagnose_usb.cpp
    )

target_include_directories(libdiagnoseusb PRIVATE
    ${SRC}/core/diagnose_usb/include
    ${SRC}/core/include
    ${SRC}/libbase/include
    )
