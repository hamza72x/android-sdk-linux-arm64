# libmdnssd - mDNS service discovery

add_library(libmdnssd STATIC
    ${SRC}/mdnsresponder/mDNSShared/dnssd_clientlib.c
    ${SRC}/mdnsresponder/mDNSShared/dnssd_clientstub.c
    ${SRC}/mdnsresponder/mDNSShared/dnssd_ipc.c
    )
target_compile_options(libmdnssd PRIVATE
    -fno-strict-aliasing
    -fwrapv
    )
target_compile_definitions(libmdnssd PRIVATE
    -D_GNU_SOURCE
    -DHAVE_IPV6
    -DNOT_HAVE_SA_LEN
    -DPLATFORM_NO_RLIMIT
    -DMDNS_UDS_SERVERPATH="/dev/socket/mdnsd"
    -DMDNS_USERNAME="mdnsr"
    -DMDNS_DEBUGMSGS=0
    )
