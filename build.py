#!/usr/bin/env python3
#
# Build orchestrator for android-sdk-linux-arm64.
# Builds Android SDK tools as native Linux ARM64 binaries.
#
# Adapted from https://github.com/lzhiyong/android-sdk-tools
# Original: Copyright 2022 Github Lzhiyong (Apache 2.0)
#

import os
import time
import shutil
import argparse
import subprocess
from pathlib import Path


def format_time(seconds):
    """Format elapsed time in human-readable form."""
    minute, sec = divmod(seconds, 60)
    hour, minute = divmod(minute, 60)
    hour, minute = int(hour), int(minute)

    if hour != 0:
        return "{}h{}m{}s".format(hour, minute, int(sec))
    elif minute != 0:
        return "{}m{}s".format(minute, int(sec))
    else:
        return "{:.2f}s".format(sec)


def build(args):
    """Run CMake configure + Ninja build for Linux native target."""
    build_dir = args.build

    command = [
        "cmake",
        "-GNinja",
        "-B", build_dir,
        "-DCMAKE_BUILD_TYPE=Release",
        "-Dprotobuf_BUILD_TESTS=OFF",
        "-DABSL_PROPAGATE_CXX_STD=ON",
    ]

    if args.protoc is not None:
        protoc_path = str(Path(args.protoc).resolve())
        if not Path(protoc_path).exists():
            raise ValueError("protoc not found: {}".format(protoc_path))
        command.append("-DPROTOC_PATH={}".format(protoc_path))

    # CMake configure
    print("\n=== CMake Configure ===")
    result = subprocess.run(command)
    if result.returncode != 0:
        print("\033[1;31mCMake configure failed!\033[0m")
        return

    # Ensure protobuf config.h exists in build directory
    # (AOSP's protobuf common.cc includes "config.h" which must be on the include path)
    protobuf_config_dir = Path(build_dir) / "src" / "protobuf"
    protobuf_config_dir.mkdir(parents=True, exist_ok=True)
    config_h = protobuf_config_dir / "config.h"
    if not config_h.exists():
        import shutil as _shutil
        _shutil.copy2("patches/misc/protobuf_config.h", config_h)

    # Ninja build
    print("\n=== Building ===")
    start_time = time.time()

    ninja_cmd = ["ninja", "-C", build_dir, "-j", str(args.job)]
    if args.target != "all":
        ninja_cmd.append(args.target)

    result = subprocess.run(ninja_cmd)

    if result.returncode == 0:
        end_time = time.time()
        print(
            "\n\033[1;32mBuild successful! Time: {}\033[0m".format(
                format_time(end_time - start_time)
            )
        )

        # List built binaries
        bin_dir = Path(build_dir) / "bin"
        if bin_dir.exists():
            print("\nBuilt binaries:")
            for subdir in ["build-tools", "platform-tools", "others"]:
                d = bin_dir / subdir
                if d.exists():
                    for f in sorted(d.iterdir()):
                        if f.is_file() and os.access(f, os.X_OK):
                            size_mb = f.stat().st_size / (1024 * 1024)
                            print("  {}: {:.1f} MB".format(f, size_mb))
    else:
        print("\n\033[1;31mBuild failed!\033[0m")


def main():
    parser = argparse.ArgumentParser(
        description="Build Android SDK tools for Linux ARM64"
    )

    parser.add_argument(
        "--build", default="build", help="Build output directory (default: build)"
    )
    parser.add_argument(
        "--job",
        default=os.cpu_count(),
        type=int,
        help="Parallel build jobs (default: nproc)",
    )
    parser.add_argument(
        "--target",
        default="all",
        help="Build specific target (e.g. aapt2, adb). Default: all",
    )
    parser.add_argument(
        "--protoc", help="Path to host protoc binary (absolute path recommended)"
    )

    args = parser.parse_args()
    build(args)


if __name__ == "__main__":
    main()
