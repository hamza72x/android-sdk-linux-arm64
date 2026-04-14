# AGENTS.md - Project Knowledge Base

## Project Overview

**android-sdk-linux-arm64** builds Android SDK tools (aapt2, aapt, aidl, zipalign, adb, fastboot, etc.) as native Linux ARM64 binaries from official AOSP source code.

This project adapts [lzhiyong/android-sdk-tools](https://github.com/lzhiyong/android-sdk-tools) (which targets Android/Bionic via NDK) to target Linux/glibc using the system compiler.

## Repository Layout

```
.
├── PLAN.md              # Detailed build plan and architecture
├── AGENTS.md            # This file - project knowledge for agents/contributors
├── README.md            # User-facing documentation
├── .gitignore           # Ignores src/ (AOSP clones) and build/ (output)
├── .github/workflows/   # CI/CD
│   ├── ci.yml           # Sanity check on push to main (verified versions only)
│   └── build.yml        # Build + Release on tag push (v*)
├── repos.json           # List of AOSP repos to clone (all android.googlesource.com)
├── versions.json        # Version registry: status, AOSP tags, release info
├── get_source.py        # Clones AOSP repos and applies patches (version-aware)
├── build.py             # Build orchestrator (CMake + Ninja, Linux native)
├── CMakeLists.txt       # Root CMake configuration
├── build-tools/         # CMake definitions for build-tools binaries
│   ├── CMakeLists.txt
│   ├── aapt.cmake
│   ├── aapt2.cmake
│   ├── aidl.cmake
│   ├── zipalign.cmake
│   ├── dexdump.cmake
│   └── split-select.cmake
├── lib/                 # CMake definitions for support libraries
│   ├── CMakeLists.txt
│   ├── libbase.cmake
│   ├── liblog.cmake
│   ├── libcutils.cmake
│   ├── libutils.cmake
│   ├── libandroidfw.cmake
│   ├── libziparchive.cmake
│   ├── libincfs.cmake
│   ├── libselinux.cmake
│   ├── libsepol.cmake
│   ├── libbuildversion.cmake
│   ├── libpackagelistparser.cmake
│   ├── libprocessgroup.cmake
│   ├── libsparse.cmake
│   ├── libusb.cmake
│   ├── libdiagnoseusb.cmake
│   ├── libmdnssd.cmake
│   ├── libopenscreen.cmake
│   ├── libabsl.cmake
│   └── libprotoc.cmake
├── platform-tools/      # CMake definitions for platform-tools binaries
│   ├── CMakeLists.txt
│   ├── adb.cmake
│   ├── fastboot.cmake
│   ├── e2fsprogs.cmake
│   ├── f2fs-tools.cmake
│   ├── hprof-conv.cmake
│   ├── sqlite3.cmake
│   └── etc1tool.cmake
├── others/              # Additional tools
│   ├── CMakeLists.txt
│   └── veridex.cmake
├── patches/             # Source patches for AOSP code (versioned)
│   ├── base/            # Universal patches (GCC/glibc compat, all versions)
│   │   ├── misc/        # Pre-generated headers and source files
│   │   │   ├── protobuf_config.h
│   │   │   ├── deployagent.inc
│   │   │   ├── deployagentscript.inc
│   │   │   ├── dex_operator_out.cc
│   │   │   ├── IncrementalProperties.sysprop.cpp
│   │   │   ├── IncrementalProperties.sysprop.h
│   │   │   └── platform_tools_version.h
│   │   ├── libbase.patch
│   │   ├── logging.patch
│   │   ├── core.patch
│   │   ├── base.patch
│   │   ├── incremental_delivery.patch
│   │   ├── openscreen.patch
│   │   ├── adb.patch
│   │   ├── aidl.patch
│   │   ├── build.patch
│   │   └── art.patch
│   ├── build-tools/     # Version-specific overrides for build-tools
│   │   └── 35.0.2/
│   │       └── misc/
│   │           └── platform_tools_version.h
│   └── platform-tools/  # Version-specific overrides for platform-tools
│       └── 35.0.2/
│           └── misc/
│               ├── deployagent.inc
│               ├── deployagentscript.inc
│               └── platform_tools_version.h
├── setup.sh             # End-user installer script
├── src/                 # [gitignored] AOSP source code (~38 repos)
└── build/               # [gitignored] CMake build output
```

## Key Technical Decisions

### 1. Linux Native vs Android NDK

The upstream lzhiyong repo builds for Android (Bionic libc) using the NDK. We target Linux (glibc) with the system compiler. Key differences:

- **No `c++_static`**: NDK's bundled libc++ is replaced by system libstdc++ (linked automatically by GCC)
- **No NDK toolchain file**: We use CMake's default native compilation
- **`-lpthread`**: Explicit pthread linking needed on Linux (Bionic includes it implicitly)
- **No `ANDROID` define**: AOSP code has `#ifdef __ANDROID__` guards; without it, Linux code paths activate

### 2. Source Origin

ALL C/C++ source code comes from `https://android.googlesource.com/platform/...` (official Google AOSP mirrors). The `repos.json` file lists every repository. No third-party source code is used beyond what AOSP itself depends on.

### 3. Protobuf Two-Stage Build

Protobuf requires a two-stage build:
1. Build `protoc` natively for the host (using AOSP's bundled protobuf with system cmake)
2. Use that `protoc` to generate `.pb.cc`/`.pb.h` files during the main build

The host `protoc` path is passed via `-DPROTOC_PATH=...` to CMake.

### 4. libcutils Android-Only Sources

The original build includes Android kernel-specific source files in libcutils. These are excluded for Linux:
- `ashmem-dev.cpp` (Android shared memory)
- `android_reboot.cpp` (Android reboot syscall)
- `trace-dev.cpp` (Android atrace)
- `klog.cpp` (kernel log)
- `qtaguid.cpp` (network tagging)
- `uevent.cpp` (kernel uevents)
- `partition_utils.cpp` (Android partitions)

### 5. liblog FAKE_LOG_DEVICE

liblog is compiled with `-DFAKE_LOG_DEVICE=1` which routes Android logging to stderr instead of the Android logd daemon. This is critical for host builds.

## Build Commands

### Full Build
```bash
# Clone AOSP sources (with version-specific patch resolution)
python3 get_source.py --tags platform-tools-35.0.2 \
    --component build-tools --version 35.0.2

# Build host protoc
cd src/protobuf && mkdir build && cd build
cmake -GNinja -Dprotobuf_BUILD_TESTS=OFF ..
ninja -j$(nproc)
cd ../../..

# Build all tools
python3 build.py --protoc=$(pwd)/src/protobuf/build/protoc
```

### Build Single Target
```bash
python3 build.py --protoc=$(pwd)/src/protobuf/build/protoc --target=aapt2
```

### Clean Build
```bash
rm -rf build/
python3 build.py --protoc=$(pwd)/src/protobuf/build/protoc
```

## Dependencies (Build Host)

### Required Packages

| Package | Purpose |
|---------|---------|
| `gcc`, `g++` | C/C++ compiler |
| `cmake` (>= 3.14) | Build system generator |
| `ninja-build` | Build executor |
| `git` | Clone AOSP repos |
| `python3` | Build scripts |
| `golang` | Required by some AOSP components |
| `bison` | Parser generator (for aidl) |
| `flex` | Lexer generator (for aidl, libsepol) |
| `zlib-devel` | Compression library |
| `openssl-devel` | Crypto (for boringssl fallback headers) |
| `libusb1-devel` | USB device access (for adb) |
| `pcre2-devel` | Regex library (for libselinux) |
| `expat-devel` | XML parsing (for aapt/aapt2) |
| `libpng-devel` | PNG processing (for aapt/aapt2) |

### Fedora/RHEL
```bash
sudo dnf install gcc gcc-c++ cmake ninja-build git python3 golang bison flex \
    zlib-devel openssl-devel libusb1-devel pcre2-devel expat-devel libpng-devel
```

### Ubuntu/Debian
```bash
sudo apt install gcc g++ cmake ninja-build git python3 golang bison flex \
    zlib1g-dev libssl-dev libusb-1.0-0-dev libpcre2-dev libexpat1-dev libpng-dev
```

## Output Binaries

After a successful build, all binaries are in `build/bin/` (flat directory):

### build-tools
| Binary | Description |
|--------|-------------|
| `aapt` | Android Asset Packaging Tool (legacy) |
| `aapt2` | Android Asset Packaging Tool 2 (used by Gradle/AGP) |
| `aidl` | Android Interface Definition Language compiler |
| `zipalign` | APK zip alignment tool |
| `dexdump` | DEX file disassembler/inspector |
| `split-select` | APK split selection tool |

### platform-tools
| Binary | Description |
|--------|-------------|
| `adb` | Android Debug Bridge |
| `fastboot` | Device bootloader flashing tool |
| `sqlite3` | SQLite CLI (Android version) |
| `etc1tool` | ETC1 texture tool |
| `hprof-conv` | HPROF converter |
| `e2fsdroid` | ext4 filesystem tool |
| `mke2fs` | ext4 filesystem creator |
| `make_f2fs` | F2FS filesystem creator |
| `make_f2fs_casefold` | F2FS filesystem creator (with casefolding) |
| `sload_f2fs` | F2FS filesystem loader |

### others
| Binary | Description |
|--------|-------------|
| `veridex` | DEX file verifier |

## Flutter Integration

For Flutter APK builds on Linux ARM64:

1. `aapt2` override: Set `android.aapt2FromMavenOverride=<path>` in gradle.properties
2. Build-tools: Place in `$ANDROID_SDK/build-tools/<version>/`
3. Platform-tools: Place `adb` in `$ANDROID_SDK/platform-tools/`
4. NDK shim: Flutter requires NDK for `llvm-strip`; create a shim directory with system `llvm-strip`

The `setup.sh` script handles all of this automatically.

## Versioning

Project versions track Android build-tools versions:
- Current target: **35.0.2** (matching `platform-tools-35.0.2` AOSP tag)
- The `TOOLS_VERSION` variable in `CMakeLists.txt` controls this
- `versions.json` is the central registry of all known versions, their verification status (`verified`/`unverified`/`shim`), AOSP tags, and release availability

### Patch Resolution Order

When `get_source.py` applies patches for a given component and version:
1. **Version-specific first**: `patches/<component>/<version>/` (e.g. `patches/build-tools/35.0.2/`)
2. **Base fallback**: `patches/base/` (universal GCC/glibc compatibility patches)

For files in `misc/`, version-specific files override base files with the same name.

### Concrete Example: Building `build-tools 35.0.2`

When you run `./setup.sh build-build-tools 35.0.2`, here is the exact patch resolution:

**Git patches** (applied to AOSP source in `src/`):
```
patches/build-tools/35.0.2/libbase.patch   → NOT FOUND → patches/base/libbase.patch ✓
patches/build-tools/35.0.2/logging.patch   → NOT FOUND → patches/base/logging.patch ✓
patches/build-tools/35.0.2/core.patch      → NOT FOUND → patches/base/core.patch ✓
...etc for all 10 patches
```

**Misc files** (pre-generated headers/source copied into `src/`):
```
platform_tools_version.h:
  patches/build-tools/35.0.2/misc/platform_tools_version.h ✓ (version-specific WINS)
  patches/base/misc/platform_tools_version.h (ignored)

protobuf_config.h:
  patches/build-tools/35.0.2/misc/protobuf_config.h → NOT FOUND
  patches/base/misc/protobuf_config.h ✓ (base fallback)

deployagent.inc, deployagentscript.inc, etc:
  patches/build-tools/35.0.2/misc/deployagent.inc → NOT FOUND
  patches/base/misc/deployagent.inc ✓ (base fallback)
```

**For `platform-tools 35.0.2`**, the same logic applies but checks `patches/platform-tools/35.0.2/` first.

**Misc files are copied to these destinations:**
| File | Destination in `src/` |
|------|----------------------|
| `platform_tools_version.h` | `src/soong/cc/libbuildversion/include/` |
| `protobuf_config.h` | `src/protobuf/build/config.h` |
| `IncrementalProperties.sysprop.h` | `src/incremental_delivery/sysprop/include/` |
| `IncrementalProperties.sysprop.cpp` | `src/incremental_delivery/sysprop/` |
| `deployagent.inc` | `src/adb/fastdeploy/deployagent/` |
| `deployagentscript.inc` | `src/adb/fastdeploy/deployagent/` |
| `dex_operator_out.cc` | (compiled directly from `patches/base/misc/`) |

## setup.sh CLI

`setup.sh` is an SDK-manager-like CLI for managing Android SDK tools on Linux ARM64:

| Command | Description |
|---------|-------------|
| `list-versions` | Show all available versions with status |
| `install-build-tools <ver>` | Download pre-built (verified) or error with guidance |
| `install-platform-tools <ver>` | Same for platform-tools |
| `install-ndk <ver>` | Create NDK shim (llvm-strip -> system strip) |
| `install-cmake [ver]` | Create CMake shim (filters Android flags) |
| `install-cmd-tools` | Install sdkmanager |
| `install-platforms [pkgs]` | Install Android platforms via sdkmanager |
| `build-build-tools <ver>` | Build from AOSP source |
| `build-platform-tools <ver>` | Build from AOSP source |
| `doctor` | Diagnose setup (checks arch per build-tools version) |
| `status` | Show what's installed |
| `setup-gradle` | Configure `android.aapt2FromMavenOverride` |

## Troubleshooting

### Common Build Issues

**Missing flex/bison**: `aidl` and `libsepol` require flex and bison for parser generation.

**Protobuf version mismatch**: If host protoc version is too new (>3.21.12), generated code may be incompatible with AOSP's bundled protobuf library. Always use the protoc built from `src/protobuf/`.

**zlib-ng on Fedora**: Fedora 43+ uses `zlib-ng-compat` instead of traditional zlib. This is a drop-in replacement and works transparently.

**GCC 15 warnings**: Some AOSP code may produce warnings with GCC 15. We suppress non-critical warnings via `-Wno-attributes` and similar flags.

### Verifying Binaries

```bash
# Check it's a native Linux ARM64 binary
file build/bin/aapt2
# Expected: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), dynamically linked ...

# Check it runs
./build/bin/aapt2 version
./build/bin/adb version
```
