#!/usr/bin/env python3
#
# Clone AOSP source repositories and apply patches for Linux ARM64 build.
#
# Patch resolution order:
#   1. patches/<component>/<version>/<patch>   (version-specific override)
#   2. patches/base/<patch>                    (base, applies to all versions)
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


def resolve_patch(patch_file, component=None, version=None):
    """Find the correct patch file, checking version-specific first, then base."""
    if component and version:
        versioned = Path("patches") / component / version / patch_file
        if versioned.exists():
            return versioned

    base = Path("patches/base") / patch_file
    if base.exists():
        return base

    return None


def resolve_misc(misc_file, component=None, version=None):
    """Find the correct misc file, checking version-specific first, then base."""
    if component and version:
        versioned = Path("patches") / component / version / "misc" / misc_file
        if versioned.exists():
            return versioned

    base = Path("patches/base/misc") / misc_file
    if base.exists():
        return base

    return None


def apply_patch(repo_dir, patch_file, component=None, version=None):
    """Apply a git patch to a repo directory."""
    patch_path = resolve_patch(patch_file, component, version)
    if patch_path is None:
        print("WARNING: Patch file {} not found".format(patch_file))
        return

    repo_path = Path("src") / repo_dir
    if not repo_path.exists():
        print("WARNING: Repo directory {} not found".format(repo_path))
        return

    # Compute relative path from repo to patch
    abs_patch = patch_path.resolve()
    abs_repo = repo_path.resolve()
    rel_patch = os.path.relpath(abs_patch, abs_repo)

    print("  Applying {} -> src/{}".format(patch_path, repo_dir))
    result = subprocess.run(
        "git apply --check {}".format(rel_patch),
        shell=True, cwd=str(repo_path),
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print("    (already applied or conflicts, skipping)")
        return
    subprocess.run(
        "git apply {}".format(rel_patch),
        shell=True, cwd=str(repo_path),
    )


def patches(component=None, version=None):
    """Apply source patches needed for the build."""
    print("Patch resolution: version-specific ({}/{}) -> base".format(
        component or "*", version or "*"))

    # ── Pre-generated files ──

    # Incremental delivery sysprop
    inc = Path.cwd() / "src/incremental_delivery/sysprop/include"
    if not inc.exists():
        inc.mkdir(parents=True)

    src_file = resolve_misc("IncrementalProperties.sysprop.h", component, version)
    if src_file:
        shutil.copy2(src_file, inc)

    src_file = resolve_misc("IncrementalProperties.sysprop.cpp", component, version)
    if src_file:
        shutil.copy2(src_file, inc.parent)

    # Deploy agent files for adb
    deploy_dir = Path("src/adb/fastdeploy/deployagent")
    if deploy_dir.exists():
        for fname in ["deployagent.inc", "deployagentscript.inc"]:
            src_file = resolve_misc(fname, component, version)
            if src_file:
                shutil.copy2(src_file, deploy_dir)

    # Platform tools version header
    version_dir = Path("src/soong/cc/libbuildversion/include")
    if version_dir.exists():
        src_file = resolve_misc("platform_tools_version.h", component, version)
        if src_file:
            shutil.copy2(src_file, version_dir)

    # Protobuf config.h
    protobuf_build = Path("src/protobuf/build")
    if not protobuf_build.exists():
        protobuf_build.mkdir(parents=True)
    src_file = resolve_misc("protobuf_config.h", component, version)
    if src_file:
        shutil.copy2(src_file, protobuf_build / "config.h")

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
    # These fix GCC / Linux glibc compatibility issues in AOSP source code.

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
        apply_patch(repo_dir, patch_file, component, version)


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
    parser.add_argument(
        "--component",
        default=None,
        help="Component name for version-specific patches (e.g. build-tools)",
    )
    parser.add_argument(
        "--version",
        default=None,
        help="Version for version-specific patches (e.g. 35.0.2)",
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
    patches(component=args.component, version=args.version)

    print("\nSource download complete!")


if __name__ == "__main__":
    main()
