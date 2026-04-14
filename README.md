# Android SDK Tools for Linux ARM64

Native ARM64 (aarch64) builds of Android SDK tools — `aapt2`, `aapt`, `aidl`, `zipalign`, `adb`, `fastboot`, and more — compiled from official AOSP source code.

Google does not publish ARM64 Linux builds of these tools. If you develop Android/Flutter apps on an ARM64 Linux machine (Asahi Linux on Apple Silicon, Raspberry Pi, Ampere/Graviton servers, etc.), this project provides them.

## Quick Start

```bash
git clone https://github.com/hamza72x/android-sdk-linux-arm64.git
cd android-sdk-linux-arm64

# See what's available
./setup.sh list-versions

# Install verified pre-built binaries
./setup.sh install-build-tools 35.0.2
./setup.sh install-platform-tools 35.0.2

# Install shims (NDK, CMake)
./setup.sh install-ndk 28.2.13676358
./setup.sh install-cmake

# Install cmdline-tools and platforms
./setup.sh install-cmd-tools
./setup.sh install-platforms android-35

# Verify everything
./setup.sh doctor
```

## How It Works

### Verified vs Unverified Versions

```
$ ./setup.sh list-versions

  build-tools
              35.0.2  [verified] (pre-built binary available)
              35.0.1  [unverified] (build from source)
              35.0.0  [unverified] (build from source)

  platform-tools
              35.0.2  [verified] (pre-built binary available)
              35.0.1  [unverified] (build from source)

  ndk
      28.2.13676358  [shim] (delegates to system tools)
      27.0.12077973  [shim] (delegates to system tools)

  cmake
               3.22.1  [shim] (delegates to system tools)
```

- **Verified** — We tested these. Pre-built ARM64 binaries are available as GitHub Releases. Just `install-*` and go.
- **Unverified** — Listed in the registry but not yet tested by us. You can build from source with `build-*` commands. If it works, submit a PR to mark it verified.
- **Shim** — Not a real build. A lightweight wrapper that delegates to your system's native tools (e.g., `llvm-strip` -> system `strip`, `cmake` -> system `cmake`).

### Patch Architecture

Patches fix GCC/glibc compatibility issues in AOSP code (which is written for Clang/Bionic):

```
patches/
  base/                  # Universal patches — apply to all AOSP versions
    *.patch              #   GCC compat, missing includes, atomics, etc.
    misc/                #   Pre-generated source files
  build-tools/
    35.0.2/              # Version-specific overrides (tested)
      *.patch            #   Patches that differ from base for this version
      misc/              #   Version-specific generated files
  platform-tools/
    35.0.2/
      misc/
```

Resolution order: **version-specific first, then base**. If `patches/build-tools/35.0.2/libbase.patch` exists it's used; otherwise `patches/base/libbase.patch` is used. This lets you override individual patches per version while sharing the common ones.

## Commands Reference

### Install Commands

These download pre-built ARM64 binaries (for verified versions) or guide you to build from source.

| Command | Description |
|---------|-------------|
| `install-build-tools <version>` | Install aapt2, aapt, aidl, zipalign, dexdump, split-select |
| `install-platform-tools <version>` | Install adb, fastboot, sqlite3, mke2fs, etc. |
| `install-ndk <version>` | Create NDK shim (llvm-strip, toolchain) |
| `install-cmake [version]` | Create CMake shim (default: 3.22.1) |
| `install-cmd-tools` | Install sdkmanager (Java-based, any arch) |
| `install-platforms [packages]` | Install Android platform SDKs |

Examples:

```bash
./setup.sh install-build-tools 35.0.2
./setup.sh install-platform-tools 35.0.2
./setup.sh install-ndk 28.2.13676358
./setup.sh install-cmake
./setup.sh install-cmd-tools
./setup.sh install-platforms android-35 android-34
```

### Build Commands

For unverified versions, or if you prefer to compile from source:

| Command | Description |
|---------|-------------|
| `build-build-tools <version>` | Clone AOSP source, apply patches, compile build-tools |
| `build-platform-tools <version>` | Clone AOSP source, apply patches, compile platform-tools |

```bash
./setup.sh build-build-tools 35.0.1    # Unverified — build yourself
./setup.sh build-platform-tools 34.0.4  # Older version
```

Building from source will:
1. Clone ~38 AOSP repos from `android.googlesource.com`
2. Apply base patches (+ version-specific overrides if they exist)
3. Build `protoc` from AOSP's bundled protobuf
4. Compile all SDK tools with CMake + Ninja

### Info Commands

| Command | Description |
|---------|-------------|
| `list-versions` | Show all known versions with verification status |
| `status` | Show what's currently installed in your SDK |
| `doctor` | Run diagnostic checks |
| `setup-gradle` | Configure Gradle aapt2 override |

### Global Options

All install/build commands accept `--sdk-root <path>` to override the SDK directory. By default it uses `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, or `~/android-sdk`.

## Flutter Setup

### 1. Install tools and shims

```bash
./setup.sh install-build-tools 35.0.2
./setup.sh install-platform-tools 35.0.2
./setup.sh install-cmd-tools
./setup.sh install-platforms android-35
```

### 2. Set up NDK shim

Check your project's `android/app/build.gradle` for `ndkVersion`, then:

```bash
./setup.sh install-ndk 28.2.13676358
./setup.sh install-cmake
```

Or auto-detect from your project directory:

```bash
cd ~/my-flutter-project
/path/to/setup.sh install-ndk    # reads ndkVersion from build.gradle
```

### 3. Set environment variables

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export ANDROID_HOME="$HOME/android-sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

### 4. Build

```bash
flutter build apk --debug
```

> **Note:** Release builds require Flutter's `gen_snapshot` AOT compiler which may not have a Linux ARM64 build depending on your Flutter version.

## Building from Source (Development)

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

Also required: **JDK 17+** (for sdkmanager).

### Manual Build

```bash
# Clone sources
python3 get_source.py --tags platform-tools-35.0.2 \
    --component build-tools --version 35.0.2

# Build protoc
cd src/protobuf && mkdir -p build && cd build
cmake -GNinja -Dprotobuf_BUILD_TESTS=OFF ..
ninja -j$(nproc) protoc
cd ../../..

# Build everything
python3 build.py --protoc=$(pwd)/src/protobuf/build/protoc

# Build single target
python3 build.py --protoc=$(pwd)/src/protobuf/build/protoc --target=aapt2
```

## Contributing New Versions

If you test a new version:

1. Add the version to `versions.json` with `"status": "unverified"`
2. Try building: `./setup.sh build-build-tools <version>`
3. If base patches work, just update the status to `"verified"` and add the `"release"` tag
4. If patches need changes, create version-specific overrides in `patches/build-tools/<version>/`
5. Submit a PR

Version-specific patches override base patches by filename. For example, if `openscreen.patch` needs a different fix for version 36.0.0:

```
patches/
  base/openscreen.patch            # Used by all other versions
  build-tools/36.0.0/openscreen.patch  # Used only for 36.0.0
```

## What's Included

### build-tools

| Binary | Description |
|--------|-------------|
| `aapt2` | Android Asset Packaging Tool 2 (used by Gradle/AGP) |
| `aapt` | Android Asset Packaging Tool (legacy) |
| `aidl` | Android Interface Definition Language compiler |
| `zipalign` | APK zip alignment tool |
| `dexdump` | DEX file disassembler/inspector |
| `split-select` | APK split selection tool |

### platform-tools

| Binary | Description |
|--------|-------------|
| `adb` | Android Debug Bridge |
| `fastboot` | Bootloader flashing tool |
| `sqlite3` | SQLite CLI (Android version) |
| `etc1tool` | ETC1 texture tool |
| `hprof-conv` | HPROF converter |
| `mke2fs` | ext4 filesystem creator |
| `e2fsdroid` | ext4 filesystem tool |
| `make_f2fs` | F2FS filesystem creator |

### Already works on ARM64 (Java-based)

- `sdkmanager`, `avdmanager` (cmdline-tools)
- `d8`, `R8` (DEX compiler)
- `apksigner` (APK signing)
- Gradle

## NDK and CMake Shims — Why?

**NDK shim:** Flutter's Gradle plugin requires NDK installed but only uses `llvm-strip` from it. Google's NDK is x86_64-only on Linux. Our shim creates the directory structure Gradle expects and points `llvm-strip` to your system's `strip`.

**CMake shim:** AGP downloads x86_64 cmake/ninja binaries. It also passes `-DCMAKE_SYSTEM_NAME=Android` to cmake, which triggers Android platform detection requiring a full NDK. Our cmake shim delegates to your system cmake and filters out these flags. This works because Flutter's CMakeLists.txt is empty (it's just a trick to make AGP download the NDK).

## Troubleshooting

### `flutter build apk` fails with "NDK not found"

```bash
grep ndkVersion android/app/build.gradle
./setup.sh install-ndk <version-from-above>
```

### `aapt2` errors during Gradle build

```bash
./setup.sh setup-gradle    # reconfigure aapt2 override
```

### `jemalloc: Unsupported system page size`

AGP's x86_64 cmake binary is running. Fix:

```bash
./setup.sh install-cmake
```

### sdkmanager installs x86_64 binaries

Expected. sdkmanager downloads x86_64 packages since Google doesn't publish ARM64 ones. Our ARM64 tools in the versioned directory take priority.

## Tested On

- Asahi Linux (Fedora 43) on Apple Silicon (M1/M2)
- GCC 15.2.1, CMake 3.31, Ninja 1.13
- Flutter 3.43.0, AGP 8.7.0

## Source & Security

All native code comes from official AOSP at `android.googlesource.com`. No third-party code. Patches are minimal GCC/glibc compatibility fixes — auditable in `patches/`.

## License

Apache 2.0 (same as AOSP).

Build system adapted from [lzhiyong/android-sdk-tools](https://github.com/lzhiyong/android-sdk-tools).
