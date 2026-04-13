#!/usr/bin/env python3
#
# Clone AOSP source repositories and apply patches for Linux ARM64 build.
#
# Adapted from https://github.com/lzhiyong/android-sdk-tools
# Original: Copyright 2022 Github Lzhiyong (Apache 2.0)
#

import os
import shutil
import argparse
import subprocess
import json
from pathlib import Path


def apply_patch(repo_dir, patch_file):
    """Apply a git patch to a repo directory."""
    patch_path = Path("patches") / patch_file
    if not patch_path.exists():
        print("WARNING: Patch file {} not found".format(patch_path))
        return
    repo_path = Path("src") / repo_dir
    if not repo_path.exists():
        print("WARNING: Repo directory {} not found".format(repo_path))
        return
    print("  Applying {} to src/{}".format(patch_file, repo_dir))
    result = subprocess.run(
        "git apply --check ../../patches/{}".format(patch_file),
        shell=True, cwd=str(repo_path),
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print("    (already applied or conflicts, skipping)")
        return
    subprocess.run(
        "git apply ../../patches/{}".format(patch_file),
        shell=True, cwd=str(repo_path),
    )


def patches():
    """Apply source patches needed for the build."""
    # ── Pre-generated files ──

    # Create include dir for incremental delivery sysprop
    inc = Path.cwd() / "src/incremental_delivery/sysprop/include"
    if not inc.exists():
        inc.mkdir(parents=True)
    shutil.copy2(Path("patches/misc/IncrementalProperties.sysprop.h"), inc)
    shutil.copy2(Path("patches/misc/IncrementalProperties.sysprop.cpp"), inc.parent)

    # Copy pre-generated deploy agent files for adb
    deploy_dir = Path("src/adb/fastdeploy/deployagent")
    if deploy_dir.exists():
        shutil.copy2(Path("patches/misc/deployagent.inc"), deploy_dir)
        shutil.copy2(Path("patches/misc/deployagentscript.inc"), deploy_dir)

    # Copy platform tools version header
    version_dir = Path("src/soong/cc/libbuildversion/include")
    if version_dir.exists():
        shutil.copy2(Path("patches/misc/platform_tools_version.h"), version_dir)

    # Copy protobuf config.h (needed by AOSP's protobuf common.cc)
    protobuf_build = Path("src/protobuf/build")
    if not protobuf_build.exists():
        protobuf_build.mkdir(parents=True)
    shutil.copy2(Path("patches/misc/protobuf_config.h"), protobuf_build / "config.h")

    # Copy dex_operator_out.cc (missing operator<< for ART enum)
    # (already in patches/misc/, referenced directly by dexdump.cmake)

    # ── Sed-based fixups ──

    # Fix googletest path in abseil-cpp
    abseil_cmake = Path.cwd() / "src/abseil-cpp/CMakeLists.txt"
    if abseil_cmake.exists():
        pattern_gtest = "'s#/usr/src/googletest#${CMAKE_SOURCE_DIR}/src/googletest#g'"
        subprocess.run(
            "sed -i {} {}".format(pattern_gtest, abseil_cmake), shell=True
        )

    # Symlink googletest into boringssl third_party
    src = Path.cwd() / "src/googletest"
    dest = Path.cwd() / "src/boringssl/src/third_party/googletest"
    if src.exists() and not dest.exists():
        subprocess.run("ln -sf {} {}".format(src, dest), shell=True)

    # ── Git diff patches ──
    # These fix GCC 15 / Linux glibc compatibility issues in AOSP source code.
    # See AGENTS.md "Discoveries" section for detailed descriptions.

    patch_map = [
        ("libbase",              "libbase.patch"),
        ("logging",              "logging.patch"),
        ("core",                 "core.patch"),
        ("base",                 "base.patch"),
        ("incremental_delivery", "incremental_delivery.patch"),
        ("openscreen",           "openscreen.patch"),
        ("adb",                  "adb.patch"),
        ("aidl",                 "aidl.patch"),
        ("build",                "build.patch"),
        ("art",                  "art.patch"),
    ]

    for repo_dir, patch_file in patch_map:
        apply_patch(repo_dir, patch_file)


def check(command):
    """Check that a required command is available."""
    try:
        subprocess.check_output(
            "command -v {}".format(command), shell=True, stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        print("ERROR: required command '{}' not found. Please install it.".format(command))
        exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Clone AOSP source repositories for android-sdk-linux-arm64"
    )
    parser.add_argument(
        "--tags",
        default="master",
        help="Git tag or branch to clone (e.g. platform-tools-35.0.2)",
    )
    args = parser.parse_args()

    # Check required tools
    for cmd in ["git", "go", "bison", "flex"]:
        check(cmd)

    # Clone AOSP repos
    with open("repos.json", "r") as f:
        repos = json.load(f)

    for repo in repos:
        if not Path(repo["path"]).exists():
            print("Cloning {} -> {}".format(repo["url"], repo["path"]))
            result = subprocess.run(
                "git clone -c advice.detachedHead=false --depth 1 --branch {} {} {}".format(
                    args.tags, repo["url"], repo["path"]
                ),
                shell=True,
            )
            if result.returncode != 0:
                print("WARNING: Failed to clone {}".format(repo["url"]))
        else:
            print("Already exists: {}".format(repo["path"]))

    # Apply patches
    print("\nApplying patches...")
    patches()

    print("\nSource download complete!")


if __name__ == "__main__":
    main()
