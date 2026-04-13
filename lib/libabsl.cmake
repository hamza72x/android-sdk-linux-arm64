# libabsl - Abseil C++ library (manual build for adb linkage)
# Note: abseil-cpp's own CMakeLists.txt is also added as a subdirectory
# in the root CMakeLists.txt. This file builds specific components that
# adb links against directly.

add_library(libabsl_base STATIC
    ${SRC}/abseil-cpp/absl/base/internal/cycleclock.cc
    ${SRC}/abseil-cpp/absl/base/internal/exponential_biased.cc
    ${SRC}/abseil-cpp/absl/base/internal/low_level_alloc.cc
    ${SRC}/abseil-cpp/absl/base/internal/periodic_sampler.cc
    ${SRC}/abseil-cpp/absl/base/internal/raw_logging.cc
    ${SRC}/abseil-cpp/absl/base/internal/spinlock.cc
    ${SRC}/abseil-cpp/absl/base/internal/spinlock_wait.cc
    ${SRC}/abseil-cpp/absl/base/internal/strerror.cc
    ${SRC}/abseil-cpp/absl/base/internal/sysinfo.cc
    ${SRC}/abseil-cpp/absl/base/internal/thread_identity.cc
    ${SRC}/abseil-cpp/absl/base/internal/throw_delegate.cc
    ${SRC}/abseil-cpp/absl/base/internal/unscaledcycleclock.cc
    )
target_include_directories(libabsl_base PUBLIC
    ${SRC}/abseil-cpp
    )

add_library(libabsl_strings STATIC
    ${SRC}/abseil-cpp/absl/strings/ascii.cc
    ${SRC}/abseil-cpp/absl/strings/charconv.cc
    ${SRC}/abseil-cpp/absl/strings/cord.cc
    ${SRC}/abseil-cpp/absl/strings/escaping.cc
    ${SRC}/abseil-cpp/absl/strings/internal/charconv_bigint.cc
    ${SRC}/abseil-cpp/absl/strings/internal/charconv_parse.cc
    ${SRC}/abseil-cpp/absl/strings/internal/cord_internal.cc
    ${SRC}/abseil-cpp/absl/strings/internal/cord_rep_ring.cc
    ${SRC}/abseil-cpp/absl/strings/internal/escaping.cc
    ${SRC}/abseil-cpp/absl/strings/internal/memutil.cc
    ${SRC}/abseil-cpp/absl/strings/internal/ostringstream.cc
    ${SRC}/abseil-cpp/absl/strings/internal/str_format/arg.cc
    ${SRC}/abseil-cpp/absl/strings/internal/str_format/bind.cc
    ${SRC}/abseil-cpp/absl/strings/internal/str_format/extension.cc
    ${SRC}/abseil-cpp/absl/strings/internal/str_format/float_conversion.cc
    ${SRC}/abseil-cpp/absl/strings/internal/str_format/output.cc
    ${SRC}/abseil-cpp/absl/strings/internal/str_format/parser.cc
    ${SRC}/abseil-cpp/absl/strings/internal/utf8.cc
    ${SRC}/abseil-cpp/absl/strings/match.cc
    ${SRC}/abseil-cpp/absl/strings/numbers.cc
    ${SRC}/abseil-cpp/absl/strings/str_cat.cc
    ${SRC}/abseil-cpp/absl/strings/str_replace.cc
    ${SRC}/abseil-cpp/absl/strings/str_split.cc
    ${SRC}/abseil-cpp/absl/strings/string_view.cc
    ${SRC}/abseil-cpp/absl/strings/substitute.cc
    )
target_include_directories(libabsl_strings PUBLIC
    ${SRC}/abseil-cpp
    )
