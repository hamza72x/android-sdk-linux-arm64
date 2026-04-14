# android-sdk-linux-arm64: Build Plan

Building Android SDK build-tools and platform-tools as **native Linux ARM64 (aarch64)** binaries, so that Flutter (and other Android development workflows) can build APKs on Linux ARM64 hosts like Asahi Linux, Raspberry Pi, Ampere servers, etc.

## Problem Statement

Google does not publish ARM64 Linux builds of the Android SDK tools. The official SDK only provides:
- `linux` (x86_64 only)
- `windows` (x86_64)
- `macosx` (universal x86_64 + arm64)

This blocks Android/Flutter development on Linux ARM64 machines. The key native binaries that need building are:

| Tool | Purpose | Status in SDK |
|------|---------|---------------|
| `aapt2` | Resource compilation & linking for APK | x86_64 native binary, no ARM64 |
| `aapt` | Legacy resource packaging | x86_64 native binary, no ARM64 |
| `aidl` | Android Interface Definition Language compiler | x86_64 native binary, no ARM64 |
| `zipalign` | APK alignment tool | x86_64 native binary, no ARM64 |
| `dexdump` | DEX file inspector | x86_64 native binary, no ARM64 |
| `adb` | Android Debug Bridge | x86_64 native binary, no ARM64 |
| `fastboot` | Device flashing tool | x86_64 native binary, no ARM64 |

Tools that already work on ARM64 (Java-based): `apksigner`, `d8`/`R8`, `sdkmanager`, Gradle.

## Upstream Reference

This project adapts [lzhiyong/android-sdk-tools](https://github.com/lzhiyong/android-sdk-tools) which builds these tools for **Android (Bionic)** using the NDK. We adapt the CMake build system to target **Linux (glibc)** using the system compiler.

### Security Audit Summary (of lzhiyong repo)

- **All source code** comes from `https://android.googlesource.com/platform/...` (official AOSP mirrors) -- verified in `repos.json`
- **Build scripts** (`get_source.py`, `build.py`) are clean Python -- no network calls during build, no suspicious code
- **CMake files** are standard `add_library`/`add_executable` patterns referencing only AOSP source
- **Patches** are small compatibility fixes (proto import paths, pre-generated headers)
- **Dead code**: `get_source.py` has an unused `download()` function (never called from `main()`)
- **License**: Apache 2.0

## Architecture

### What We Build From Source

All tools are compiled from official AOSP source code, pulled via shallow git clones:

```
AOSP Source (android.googlesource.com)
  -> ~38 repositories cloned into src/
  -> CMake build system (our adaptation)
  -> Native Linux aarch64 ELF binaries
```

### Key Adaptation: NDK -> Linux Native

The original repo uses Android NDK (Bionic libc, NDK's `c++_static`). Our changes:

| Aspect | Original (lzhiyong) | Our Adaptation |
|--------|---------------------|----------------|
| Toolchain | Android NDK (clang, bionic) | System GCC/Clang (glibc) |
| C++ stdlib | `c++_static` (NDK libc++) | System `libstdc++` (automatic) |
| Target OS | Android | Linux |
| CMake config | `CMAKE_TOOLCHAIN_FILE=ndk/.../android.toolchain.cmake` | No toolchain file (native) |
| Threading | Bionic pthreads | glibc pthreads (`-lpthread`) |
| Output | Android ELF (runs in Termux) | Linux ELF (runs on host) |

### Changes from Upstream (by category)

**1. Remove `c++_static` from link libraries (~10 files)**
The NDK bundles its own libc++ as `c++_static`. On Linux with GCC, the C++ standard library links automatically.

**2. Root CMakeLists.txt: remove NDK toolchain**
Remove `ANDROID_*` variables, `CMAKE_SYSTEM_NAME=Android`, NDK toolchain file. Add `find_package(Threads)`.

**3. Add `pthread` linkage (~5 files)**
Several tools/libraries need explicit pthread on Linux (adb, libutils, fastboot).

**4. Trim Android-only sources from `libcutils`**
Files like `ashmem-dev.cpp`, `android_reboot.cpp`, `trace-dev.cpp` use Android kernel APIs not available on Linux. Exclude them.

**5. New `build.py` for Linux**
Rewritten to invoke CMake with system compiler instead of NDK.

## Build Phases

### Phase 0: Prerequisites

```bash
# Fedora/RHEL
sudo dnf install gcc gcc-c++ cmake ninja-build git python3 golang bison flex \
    zlib-devel openssl-devel libusb1-devel pcre2-devel expat-devel libpng-devel

# Ubuntu/Debian
sudo apt install gcc g++ cmake ninja-build git python3 golang bison flex \
    zlib1g-dev libssl-dev libusb-1.0-0-dev libpcre2-dev libexpat1-dev libpng-dev
```

### Phase 1: Clone AOSP Sources

```bash
python3 get_source.py --tags platform-tools-35.0.2
```

Clones ~38 AOSP repos into `src/` (shallow clones, ~2-4 GB total).

### Phase 2: Build Host Protobuf (protoc)

```bash
cd src/protobuf && mkdir build && cd build
cmake -GNinja -Dprotobuf_BUILD_TESTS=OFF ..
ninja -j$(nproc)
```

Produces a native `protoc` binary needed to generate `.pb.cc`/`.pb.h` from proto definitions.

### Phase 3: Build All Tools

```bash
python3 build.py --protoc=$(pwd)/src/protobuf/build/protoc
```

This runs CMake + Ninja targeting the following executables:
- **build-tools**: `aapt`, `aapt2`, `aidl`, `zipalign`, `dexdump`, `split-select`
- **platform-tools**: `adb`, `fastboot`, `sqlite3`, `etc1tool`, `hprof-conv`, `e2fsprogs`, `f2fs-tools`

### Phase 4: Validate

```bash
./build/bin/aapt2 version
./build/bin/adb version
./build/bin/zipalign --help
```

### Phase 5: Install for Flutter

The `setup.sh` script automates this:

1. Downloads pre-built binaries from GitHub Releases
2. Places them in the Android SDK directory structure
3. Sets `android.aapt2FromMavenOverride` in `~/.gradle/gradle.properties`
4. Creates NDK shims (symlinks `llvm-strip` to system strip)
5. Verifies installation

## Directory Structure

```
android-sdk-linux-arm64/
  PLAN.md                       # This file
  AGENTS.md                     # Agent/contributor guide
  .gitignore                    # Ignore src/, build/
  repos.json                    # AOSP repository list (from lzhiyong)
  versions.json                 # Version registry (status, AOSP tags, releases)
  get_source.py                 # AOSP source downloader (version-aware patches)
  build.py                      # Linux native build orchestrator
  CMakeLists.txt                # Root CMake (adapted for Linux)
  build-tools/                  # CMake configs for build-tools
    CMakeLists.txt
    aapt.cmake
    aapt2.cmake
    aidl.cmake
    zipalign.cmake
    dexdump.cmake
    split-select.cmake
  lib/                          # CMake configs for support libraries
    CMakeLists.txt
    lib*.cmake                  # ~19 library definitions
  platform-tools/               # CMake configs for platform-tools
    CMakeLists.txt
    adb.cmake
    fastboot.cmake
    ...
  others/                       # Additional tools
    CMakeLists.txt
    veridex.cmake
  patches/                      # AOSP source patches (versioned)
    base/                       # Universal patches (GCC/glibc compat)
      misc/                     # Pre-generated headers
      *.patch                   # Compatibility patches
    build-tools/<version>/      # Version-specific overrides
      misc/                     # Version-specific generated files
    platform-tools/<version>/   # Version-specific overrides
      misc/                     # Version-specific generated files
  setup.sh                      # SDK-manager-like CLI installer
  src/                          # [gitignored] AOSP source clones
  build/                        # [gitignored] Build output
```

## Flutter Integration

For a Flutter project to build APKs on Linux ARM64, after running `setup.sh`:

1. **aapt2** is overridden via `android.aapt2FromMavenOverride` in gradle.properties
2. **zipalign** and other build-tools are placed in `$ANDROID_SDK/build-tools/<version>/`
3. **adb** is placed in `$ANDROID_SDK/platform-tools/`
4. **NDK**: Flutter requires NDK but it's only for `llvm-strip`. The setup script creates a shim directory pointing to system LLVM tools.
5. **Java tools** (d8, R8, apksigner, Gradle) work natively via JVM -- no changes needed.

## Release Strategy

- GitHub Releases with pre-built aarch64 Linux binaries
- Versioned to match Android build-tools versions (e.g., `35.0.2`)
- `versions.json` tracks verification status (`verified`/`unverified`/`shim`)
- `setup.sh` provides SDK-manager-like CLI:
  - `install-build-tools <ver>` / `install-platform-tools <ver>` — download pre-built
  - `build-build-tools <ver>` / `build-platform-tools <ver>` — build from AOSP source
  - `install-ndk <ver>` / `install-cmake [ver]` — create shims
  - `doctor` / `status` — diagnostic and status commands
- CI/CD via GitHub Actions ARM64 runners (when available) or self-hosted

## Known Limitations

1. **Only tested on aarch64** -- x86_64 Linux users don't need this (Google provides official builds)
2. **Patch files are version-specific** -- updating to a new build-tools version may require patch adjustments
3. **Not all platform-tools are built** -- we focus on the tools needed for development workflows
4. **No incremental updates** -- each release is a full binary set
