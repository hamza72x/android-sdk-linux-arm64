# Contributing

This document covers the internals of the build system for developers who want to add new AOSP versions, fix build issues, or understand how things work under the hood.

For end-user usage, see [README.md](README.md).

## Architecture Overview

This project compiles Android SDK tools (written for Clang/Bionic) as native Linux ARM64 binaries using GCC/glibc. The build system is:

1. **`get_source.py`** — Clones ~38 AOSP repos from `android.googlesource.com` and applies GCC/glibc compatibility patches
2. **`build.py`** — Runs CMake + Ninja to compile everything
3. **`setup.sh`** — User-facing CLI that orchestrates both scripts and installs binaries into the Android SDK directory

```
get_source.py          build.py               setup.sh
  clone AOSP ──→ src/   cmake+ninja ──→ build/   copy ──→ $ANDROID_HOME/
  apply patches          bin/                      build-tools/<ver>/
                                                   platform-tools/
```

## Repository Layout

```
.
├── setup.sh                 # End-user CLI (install, build, doctor, etc.)
├── get_source.py            # Clones AOSP repos, applies patches
├── build.py                 # CMake + Ninja build orchestrator
├── repos.json               # List of ~38 AOSP repos to clone
├── versions.json            # Version registry (status, AOSP tags, releases)
├── CMakeLists.txt           # Root CMake configuration
├── build-tools/             # CMake definitions for build-tools binaries
│   ├── CMakeLists.txt
│   ├── aapt.cmake
│   ├── aapt2.cmake
│   ├── aidl.cmake
│   ├── zipalign.cmake
│   ├── dexdump.cmake
│   └── split-select.cmake
├── platform-tools/          # CMake definitions for platform-tools binaries
│   ├── CMakeLists.txt
│   ├── adb.cmake
│   ├── fastboot.cmake
│   ├── e2fsprogs.cmake
│   ├── f2fs-tools.cmake
│   ├── hprof-conv.cmake
│   ├── sqlite3.cmake
│   └── etc1tool.cmake
├── lib/                     # CMake definitions for support libraries
│   ├── CMakeLists.txt
│   ├── libbase.cmake, liblog.cmake, libcutils.cmake, ...
│   └── (~20 library cmake files)
├── others/                  # Additional tools
│   ├── CMakeLists.txt
│   └── veridex.cmake
├── patches/                 # Source patches (see Patch System below)
│   ├── base/                # Universal patches (all versions)
│   ├── build-tools/         # Version-specific overrides
│   └── platform-tools/      # Version-specific overrides
├── .github/workflows/
│   ├── ci.yml               # Sanity check on push to main
│   └── build.yml            # Build + Release on tag push
├── src/                     # [gitignored] AOSP source code (~2-4 GB)
└── build/                   # [gitignored] CMake build output
```

## Manual Build (Step by Step)

This is what `setup.sh build-build-tools <version>` does under the hood. You only need this if you're hacking on the build system itself.

### Prerequisites

**Fedora / RHEL / Asahi Linux:**
```bash
sudo dnf install gcc gcc-c++ cmake ninja-build git python3 golang bison flex \
    zlib-devel openssl-devel libusb1-devel pcre2-devel expat-devel libpng-devel
```

**Ubuntu / Debian:**
```bash
sudo apt install gcc g++ cmake ninja-build git python3 golang bison flex \
    zlib1g-dev libssl-dev libusb-1.0-0-dev libpcre2-dev libexpat1-dev libpng-dev
```

### Step 1: Clone AOSP Sources

```bash
python3 get_source.py --tags platform-tools-35.0.2 \
    --component build-tools --version 35.0.2
```

This clones ~38 repos into `src/` and applies patches from `patches/`. The `--component` and `--version` flags control which version-specific patches to use (see [Patch System](#patch-system) below).

**Re-running for a different version:** `get_source.py` automatically resets patched repos (`git checkout . && git clean -fd`) before applying new patches, so switching between versions is safe without deleting `src/`.

After cloning, `src/` looks like:

```
src/
├── adb/
├── aidl/
├── art/
├── base/
├── boringssl/
├── core/
├── protobuf/
├── ... (~38 repos total, ~2-4 GB)
```

### Step 2: Build Protoc

AOSP bundles its own protobuf (older than system protobuf). We must build AOSP's `protoc` first, then use it to generate `.pb.cc`/`.pb.h` files during the main build. Using system protoc would cause version mismatches.

```bash
mkdir -p src/protobuf/build

# Copy the protobuf config.h (version-specific -> base fallback)
cp patches/base/misc/protobuf_config.h src/protobuf/build/config.h

cmake -GNinja \
    -B src/protobuf/build \
    -S src/protobuf \
    -Dprotobuf_BUILD_TESTS=OFF
ninja -C src/protobuf/build -j$(nproc) protoc
```

Output: `src/protobuf/build/protoc`

### Step 3: Build All Tools

```bash
# Build with versioned build directory
python3 build.py \
    --protoc=$(pwd)/src/protobuf/build/protoc \
    --build=build/build-tools-35.0.2
```

Or build a single target:

```bash
python3 build.py \
    --protoc=$(pwd)/src/protobuf/build/protoc \
    --build=build/build-tools-35.0.2 \
    --target=aapt2
```

The `--build` flag controls where CMake output goes. Using `build/<component>-<version>` keeps builds isolated so you can have multiple versions built side by side.

Output: all binaries go to `build/<component>-<version>/bin/` (flat directory):

```
build/build-tools-35.0.2/bin/
├── aapt2, aapt, aidl, zipalign, dexdump, split-select     # build-tools
├── adb, fastboot, sqlite3, etc1tool, hprof-conv            # platform-tools
├── mke2fs, e2fsdroid, make_f2fs, make_f2fs_casefold, sload_f2fs
└── veridex                                                  # others
```

### Step 4: Install into SDK

Copy the binaries to the right places:

```bash
# build-tools
mkdir -p $ANDROID_HOME/build-tools/35.0.2
cp build/build-tools-35.0.2/bin/{aapt,aapt2,aidl,zipalign,dexdump,split-select} $ANDROID_HOME/build-tools/35.0.2/

# platform-tools
mkdir -p $ANDROID_HOME/platform-tools
cp build/build-tools-35.0.2/bin/{adb,fastboot,sqlite3,etc1tool,hprof-conv,mke2fs,e2fsdroid,make_f2fs,make_f2fs_casefold,sload_f2fs} $ANDROID_HOME/platform-tools/
```

Or just use `setup.sh` which does all of this automatically.

## Patch System

### Why Patches?

AOSP code is written for Clang + Bionic (Android's libc). Building with GCC + glibc requires fixes:

- `__builtin_available(android 30, *)` — Clang-only, replaced with `false`
- C11 `<stdatomic.h>` in C++ — works in Clang C++ mode but not GCC
- Missing `#include` headers — GCC 15 is stricter than Clang
- Thread safety annotations — made no-op on non-Clang
- `_Nonnull`/`_Nullable` — defined as empty for non-Clang
- And ~15 more fixes (see `AGENTS.md` for the full list)

### Patch Resolution Order

When `get_source.py` applies patches for a given component and version:

1. **Version-specific first**: `patches/<component>/<version>/`
2. **Base fallback**: `patches/base/`

```
patches/
├── base/                          # Universal patches — all versions
│   ├── *.patch                    # Git diff patches
│   └── misc/                      # Pre-generated source files
│       ├── protobuf_config.h
│       ├── platform_tools_version.h
│       ├── deployagent.inc
│       ├── deployagentscript.inc
│       ├── dex_operator_out.cc
│       ├── IncrementalProperties.sysprop.cpp
│       └── IncrementalProperties.sysprop.h
├── build-tools/
│   └── 35.0.2/                    # Version-specific overrides
│       └── misc/
│           └── platform_tools_version.h  # Overrides base version
└── platform-tools/
    └── 35.0.2/
        └── misc/
            ├── deployagent.inc           # Overrides base version
            ├── deployagentscript.inc
            └── platform_tools_version.h
```

### Concrete Example: Building build-tools 35.0.2

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
```

**Misc file destinations:**

| File | Destination in `src/` |
|------|----------------------|
| `platform_tools_version.h` | `src/soong/cc/libbuildversion/include/` |
| `protobuf_config.h` | `src/protobuf/build/config.h` |
| `IncrementalProperties.sysprop.h` | `src/incremental_delivery/sysprop/include/` |
| `IncrementalProperties.sysprop.cpp` | `src/incremental_delivery/sysprop/` |
| `deployagent.inc` | `src/adb/fastdeploy/deployagent/` |
| `deployagentscript.inc` | `src/adb/fastdeploy/deployagent/` |
| `dex_operator_out.cc` | (compiled directly from `patches/base/misc/`) |

## Adding a New Version

### 1. Add to versions.json

```json
{
  "build-tools": {
    "36.0.0": {
      "status": "unverified",
      "aosp_tag": "platform-tools-36.0.0",
      "notes": "Not yet tested"
    }
  }
}
```

### 2. Try building

```bash
./setup.sh build-build-tools 36.0.0
```

### 3. If base patches work

Update `versions.json`:
- Set `"status": "verified"`
- Add `"release": "v36.0.0"`
- Add `"tested_on"` info

### 4. If patches need changes

Create version-specific overrides. Only the patches that differ need to be overridden:

```
patches/
  base/openscreen.patch                # Used by all other versions
  build-tools/36.0.0/openscreen.patch  # Used only for 36.0.0
```

### 5. Submit a PR

The CI workflow will build and verify all binaries are ARM64.

## Key Technical Decisions

### Linux Native vs Android NDK

The upstream [lzhiyong/android-sdk-tools](https://github.com/lzhiyong/android-sdk-tools) builds for Android (Bionic libc) using the NDK. We target Linux (glibc) with the system compiler:

- **No `c++_static`**: NDK's bundled libc++ is replaced by system libstdc++
- **No NDK toolchain file**: CMake's default native compilation
- **`-lpthread`**: Explicit pthread linking (Bionic includes it implicitly)
- **No `ANDROID` define**: `#ifdef __ANDROID__` guards activate Linux code paths

### Protobuf Two-Stage Build

Protobuf requires building `protoc` first (host tool), then using it during the main build to generate `.pb.cc`/`.pb.h` files. The host `protoc` path is passed via `-DPROTOC_PATH=...` to CMake.

Always use the AOSP-bundled protobuf, not system protobuf. Version mismatches between protoc and the protobuf library cause build failures.

### libcutils Android-Only Sources

These are excluded from the Linux build (they require Android kernel interfaces):

- `ashmem-dev.cpp`, `android_reboot.cpp`, `trace-dev.cpp`, `klog.cpp`
- `qtaguid.cpp`, `uevent.cpp`, `partition_utils.cpp`

### liblog FAKE_LOG_DEVICE

liblog is compiled with `-DFAKE_LOG_DEVICE=1` which routes Android logging to stderr instead of the Android logd daemon.

## CI/CD

### ci.yml — Sanity Check

Triggered on push to `main` and PRs. Builds all verified versions (matrix strategy) on `ubuntu-24.04-arm` (native ARM64). Verifies every binary with `file` to confirm it's `aarch64`. Does NOT create releases.

### build.yml — Build & Release

Triggered on tag push (`v*`) or manual dispatch. Builds everything and creates a GitHub Release with 3 tarballs:

- `android-sdk-linux-arm64-build-tools-<version>.tar.gz`
- `android-sdk-linux-arm64-platform-tools-<version>.tar.gz`
- `android-sdk-linux-arm64-v<version>.tar.gz` (combined, for backward compat)

To create a release:

```bash
git tag v35.0.2
git push origin v35.0.2
```

## Troubleshooting Build Issues

### Missing flex/bison

`aidl` and `libsepol` require flex and bison for parser generation.

### Protobuf version mismatch

If host protoc version is too new (>3.21.12), generated code may be incompatible with AOSP's bundled protobuf library. Always use the protoc built from `src/protobuf/`.

### zlib-ng on Fedora

Fedora 43+ uses `zlib-ng-compat` instead of traditional zlib. This is a drop-in replacement and works transparently.

### GCC 15 warnings

Some AOSP code may produce warnings with GCC 15. We suppress non-critical warnings via `-Wno-attributes` and similar flags.

### Static library link ordering

GCC is strict about link order (unlike Clang). If you see undefined symbol errors, the fix is usually `target_link_libraries` for dependency propagation or `--start-group`/`--end-group` for circular dependencies (used for adb).
