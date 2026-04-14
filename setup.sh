#!/usr/bin/env bash
#
# setup.sh - Android SDK Manager for Linux ARM64
#
# Manages Android SDK tools on aarch64 Linux where Google provides no
# native binaries. Downloads pre-built releases or builds from AOSP source.
#
# Usage:
#   ./setup.sh list-versions                 # Show all available versions
#   ./setup.sh install-build-tools 35.0.2    # Install build-tools
#   ./setup.sh install-platform-tools 35.0.2 # Install platform-tools
#   ./setup.sh install-ndk 28.2.13676358     # Create NDK shim
#   ./setup.sh install-cmake 3.22.1          # Create CMake shim
#   ./setup.sh install-cmd-tools             # Install sdkmanager
#   ./setup.sh install-platforms android-35   # Install Android platform
#   ./setup.sh build-build-tools 35.0.2      # Build from AOSP source
#   ./setup.sh build-platform-tools 35.0.2   # Build from AOSP source
#   ./setup.sh doctor                        # Diagnose setup
#   ./setup.sh setup-gradle                  # Configure Gradle aapt2 override
#
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────

REPO_OWNER="hamza72x"
REPO_NAME="android-sdk-linux-arm64"
REPO="${REPO_OWNER}/${REPO_NAME}"
REPO_URL="https://github.com/${REPO}"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# Build-tools binaries (native, need ARM64 builds)
BUILD_TOOLS_BINS=(aapt aapt2 aidl zipalign dexdump split-select)

# Platform-tools binaries (native, need ARM64 builds)
PLATFORM_TOOLS_BINS=(adb fastboot sqlite3 etc1tool hprof-conv mke2fs e2fsdroid make_f2fs make_f2fs_casefold sload_f2fs)

# Build dependencies by distro family
DEPS_FEDORA="gcc gcc-c++ cmake ninja-build git python3 golang bison flex zlib-devel openssl-devel libusb1-devel pcre2-devel expat-devel libpng-devel"
DEPS_DEBIAN="gcc g++ cmake ninja-build git python3 golang bison flex zlib1g-dev libssl-dev libusb-1.0-0-dev libpcre2-dev libexpat1-dev libpng-dev"

# ── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "${BLUE}::${NC} $*"; }
ok()      { echo -e "${GREEN}::${NC} $*"; }
warn()    { echo -e "${YELLOW}:: WARNING:${NC} $*"; }
err()     { echo -e "${RED}:: ERROR:${NC} $*"; }
die()     { err "$@"; exit 1; }
header()  { echo ""; echo -e "${BOLD}$*${NC}"; echo -e "${DIM}$(printf '%.0s─' $(seq 1 60))${NC}"; }

# ── Globals ────────────────────────────────────────────────────────────────────

SDK_ROOT=""
SCRIPT_DIR=""

# ── Helper functions ───────────────────────────────────────────────────────────

check_command() { command -v "$1" &>/dev/null; }
require_command() {
    if ! check_command "$1"; then
        die "Required command '$1' not found. Please install it."
    fi
}

check_arch() {
    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "aarch64" && "$arch" != "arm64" ]]; then
        die "This tool only supports Linux ARM64 (aarch64), but you are on: $arch"
    fi
}

# Resolve the directory where this script lives (for finding versions.json, etc.)
resolve_script_dir() {
    if [[ -n "$SCRIPT_DIR" ]]; then return; fi
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        SCRIPT_DIR="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$SCRIPT_DIR/$source"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$source")" && pwd)"
}

# Detect or ask for SDK root
detect_sdk_root() {
    if [[ -n "$SDK_ROOT" ]]; then
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (--sdk-root)"
        return
    fi

    if [[ -n "${ANDROID_HOME:-}" ]]; then
        SDK_ROOT="$ANDROID_HOME"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (from \$ANDROID_HOME)"
    elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        SDK_ROOT="$ANDROID_SDK_ROOT"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (from \$ANDROID_SDK_ROOT)"
    elif [[ -d "$HOME/Android/Sdk" ]]; then
        SDK_ROOT="$HOME/Android/Sdk"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (found ~/Android/Sdk)"
    elif [[ -d "$HOME/android-sdk" ]]; then
        SDK_ROOT="$HOME/android-sdk"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (found ~/android-sdk)"
    else
        SDK_ROOT="$HOME/android-sdk"
        echo ""
        echo -e "  No Android SDK found. Default: ${BOLD}$SDK_ROOT${NC}"
        read -rp "  Use this path? [Y/n] or enter a custom path: " answer
        case "$answer" in
            ""|[Yy]*) ;;
            [Nn]*)   read -rp "  Enter SDK path: " SDK_ROOT ;;
            *)       SDK_ROOT="$answer" ;;
        esac
        SDK_ROOT="${SDK_ROOT/#\~/$HOME}"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (new)"
    fi

    mkdir -p "$SDK_ROOT"
    SDK_ROOT="$(cd "$SDK_ROOT" && pwd)"
}

# ── versions.json handling ─────────────────────────────────────────────────────

# Read versions.json — either from the local repo or fetch from GitHub
get_versions_json() {
    resolve_script_dir

    local local_path="${SCRIPT_DIR}/versions.json"
    if [[ -f "$local_path" ]]; then
        cat "$local_path"
        return
    fi

    # Fetch from GitHub
    local tmpfile
    tmpfile="$(mktemp)"
    if curl -fsSL "${RAW_URL}/versions.json" -o "$tmpfile" 2>/dev/null; then
        cat "$tmpfile"
        rm -f "$tmpfile"
        return
    fi
    rm -f "$tmpfile"
    die "Could not find versions.json locally or fetch from GitHub."
}

# Query a field from versions.json
# Usage: versions_query '.["build-tools"]["35.0.2"]["status"]'
versions_query() {
    local json
    json="$(get_versions_json)"
    echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
path = sys.argv[1]
# Simple path parser: .key1.key2.key3 or .[\"key1\"][\"key2\"]
import re
keys = re.findall(r'\[\"([^\"]+)\"\]|\.(\w+)', path)
obj = data
for k in keys:
    key = k[0] or k[1]
    if isinstance(obj, dict) and key in obj:
        obj = obj[key]
    else:
        sys.exit(1)
print(json.dumps(obj) if isinstance(obj, (dict, list)) else obj)
" "$1" 2>/dev/null
}

# Get AOSP tag for a component version
get_aosp_tag() {
    local component="$1" version="$2"
    versions_query ".[\"${component}\"][\"${version}\"][\"aosp_tag\"]"
}

# Get status for a component version
get_status() {
    local component="$1" version="$2"
    versions_query ".[\"${component}\"][\"${version}\"][\"status\"]"
}

# Get release tag for a component version
get_release_tag() {
    local component="$1" version="$2"
    versions_query ".[\"${component}\"][\"${version}\"][\"release\"]"
}

# ── list-versions ──────────────────────────────────────────────────────────────

cmd_list_versions() {
    local json
    json="$(get_versions_json)"

    header "Available Versions"

    echo "$json" | python3 -c "
import sys, json

data = json.load(sys.stdin)

GREEN  = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN   = '\033[0;36m'
DIM    = '\033[2m'
BOLD   = '\033[1m'
NC     = '\033[0m'

for component in ['build-tools', 'platform-tools', 'ndk', 'cmake', 'cmdline-tools']:
    if component not in data:
        continue
    print(f'\n  {BOLD}{component}{NC}')
    versions = data[component]
    for ver in sorted(versions.keys(), key=lambda v: [int(x) for x in v.split('.') if x.isdigit()], reverse=True):
        info = versions[ver]
        status = info.get('status', 'unknown')
        notes  = info.get('notes', '')
        release = info.get('release', '')

        if status == 'verified':
            badge = f'{GREEN}verified{NC}'
            extra = f' {DIM}(pre-built binary available){NC}' if release else ''
        elif status == 'shim':
            badge = f'{CYAN}shim{NC}'
            extra = f' {DIM}(delegates to system tools){NC}'
        else:
            badge = f'{YELLOW}unverified{NC}'
            extra = f' {DIM}(build from source){NC}'

        print(f'    {ver:>20s}  [{badge}]{extra}')
        if notes:
            print(f'                         {DIM}{notes}{NC}')
print()
"
}

# ── install-build-tools ────────────────────────────────────────────────────────

cmd_install_build_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 install-build-tools <version>\n  Run '$0 list-versions' to see available versions."
    fi
    shift

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root

    local status
    status="$(get_status "build-tools" "$version" 2>/dev/null || echo "")"

    if [[ -z "$status" ]]; then
        die "Version $version not found in versions.json.\n  Run '$0 list-versions' to see available versions."
    fi

    local bt_dir="$SDK_ROOT/build-tools/${version}"

    header "Install build-tools ${version}"
    echo "  SDK root:    $SDK_ROOT"
    echo "  Destination: $bt_dir"
    echo "  Status:      $status"
    echo ""

    if [[ "$status" == "verified" ]]; then
        local release_tag
        release_tag="$(get_release_tag "build-tools" "$version" 2>/dev/null || echo "")"

        if [[ -n "$release_tag" ]]; then
            # Download pre-built binary
            download_and_install_release "$release_tag" "$bt_dir" "build-tools"
        else
            warn "No pre-built binary available for ${version}."
            info "Building from source instead..."
            build_tools_from_source "build-tools" "$version"
        fi
    else
        warn "Version ${version} is unverified — no pre-built binary available."
        echo ""
        echo "  Options:"
        echo "    1. Build from source:  $0 build-build-tools ${version}"
        echo "    2. Use a verified version: $0 list-versions"
        echo ""
        die "Use 'build-build-tools' to build unverified versions from source."
    fi

    # source.properties
    create_source_properties "$bt_dir" "Android SDK Build-Tools ${version}" "$version"

    # Configure gradle aapt2 override
    configure_gradle "${bt_dir}/aapt2"

    ok "build-tools ${version} installed to ${bt_dir}"
}

# ── install-platform-tools ─────────────────────────────────────────────────────

cmd_install_platform_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 install-platform-tools <version>\n  Run '$0 list-versions' to see available versions."
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root

    local status
    status="$(get_status "platform-tools" "$version" 2>/dev/null || echo "")"

    if [[ -z "$status" ]]; then
        die "Version $version not found in versions.json.\n  Run '$0 list-versions' to see available versions."
    fi

    local pt_dir="$SDK_ROOT/platform-tools"

    header "Install platform-tools ${version}"
    echo "  SDK root:    $SDK_ROOT"
    echo "  Destination: $pt_dir"
    echo "  Status:      $status"
    echo ""

    if [[ "$status" == "verified" ]]; then
        local release_tag
        release_tag="$(get_release_tag "platform-tools" "$version" 2>/dev/null || echo "")"

        if [[ -n "$release_tag" ]]; then
            download_and_install_release "$release_tag" "$pt_dir" "platform-tools"
        else
            warn "No pre-built binary available."
            info "Building from source instead..."
            build_tools_from_source "platform-tools" "$version"
        fi
    else
        warn "Version ${version} is unverified."
        echo ""
        echo "  Build from source:  $0 build-platform-tools ${version}"
        echo ""
        die "Use 'build-platform-tools' to build unverified versions."
    fi

    ok "platform-tools ${version} installed to ${pt_dir}"
}

# ── install-ndk ────────────────────────────────────────────────────────────────

cmd_install_ndk() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        # Try auto-detect from current directory
        local detected
        if detected="$(detect_ndk_version .)"; then
            info "Detected ndkVersion from project: ${detected}"
            read -rp "  Create NDK shim for ${detected}? [Y/n] " confirm
            [[ "$confirm" =~ ^[Nn] ]] && exit 0
            version="$detected"
        else
            die "Usage: $0 install-ndk <version>\n  Example: $0 install-ndk 28.2.13676358\n  Run from a Flutter project dir to auto-detect."
        fi
    else
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    detect_sdk_root
    create_ndk_shim "$version"
    create_cmake_shim "3.22.1"
    ok "NDK ${version} shim ready."
}

# ── install-cmake ──────────────────────────────────────────────────────────────

cmd_install_cmake() {
    local version="${1:-3.22.1}"
    [[ $# -gt 0 ]] && shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    detect_sdk_root
    create_cmake_shim "$version"
    ok "CMake ${version} shim ready."
}

# ── install-cmd-tools ──────────────────────────────────────────────────────────

cmd_install_cmd_tools() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    detect_sdk_root
    ensure_cmdline_tools
    accept_licenses
    ok "Command-line tools installed."
}

# ── install-platforms ──────────────────────────────────────────────────────────

cmd_install_platforms() {
    detect_sdk_root
    ensure_cmdline_tools

    if [[ $# -gt 0 ]]; then
        accept_licenses
        info "Installing: $*"
        # Prefix with "platforms;" if user passed bare version like "android-35"
        local packages=()
        for arg in "$@"; do
            case "$arg" in
                --sdk-root) SDK_ROOT="$2"; shift; continue ;;
                platforms\;*|build-tools\;*|sources\;*|system-images\;*|add-ons\;*)
                    packages+=("$arg") ;;
                android-*)
                    packages+=("platforms;${arg}") ;;
                *)
                    packages+=("$arg") ;;
            esac
        done
        run_sdkmanager "${packages[@]}"
    else
        header "Install Android Platforms"
        echo "  Common packages:"
        echo ""
        echo "    android-36    (Android 16 / Baklava)"
        echo "    android-35    (Android 15)"
        echo "    android-34    (Android 14)"
        echo "    android-33    (Android 13)"
        echo ""
        read -rp "  Packages to install (space-separated): " input

        if [[ -n "$input" ]]; then
            accept_licenses
            local packages=()
            for arg in $input; do
                case "$arg" in
                    platforms\;*) packages+=("$arg") ;;
                    android-*)    packages+=("platforms;${arg}") ;;
                    *)            packages+=("$arg") ;;
                esac
            done
            run_sdkmanager "${packages[@]}"
        fi
    fi
}

# ── build-build-tools ──────────────────────────────────────────────────────────

cmd_build_build_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 build-build-tools <version>"
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root
    build_tools_from_source "build-tools" "$version"

    local bt_dir="$SDK_ROOT/build-tools/${version}"
    create_source_properties "$bt_dir" "Android SDK Build-Tools ${version}" "$version"
    configure_gradle "${bt_dir}/aapt2"
    ok "build-tools ${version} built and installed."
}

# ── build-platform-tools ──────────────────────────────────────────────────────

cmd_build_platform_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 build-platform-tools <version>"
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root
    build_tools_from_source "platform-tools" "$version"
    ok "platform-tools ${version} built and installed."
}

# ── setup-gradle ───────────────────────────────────────────────────────────────

cmd_setup_gradle() {
    detect_sdk_root

    # Find latest build-tools with ARM64 aapt2
    local bt_dir="$SDK_ROOT/build-tools"
    local latest=""
    if [[ -d "$bt_dir" ]]; then
        for d in $(ls -d "$bt_dir"/*/ 2>/dev/null | sort -V -r); do
            if [[ -x "${d}aapt2" ]]; then
                local ftype
                ftype=$(file -b "${d}aapt2" 2>/dev/null)
                if [[ "$ftype" == *"aarch64"* || "$ftype" == *"ARM aarch64"* ]]; then
                    latest="${d}aapt2"
                    break
                fi
            fi
        done
    fi

    if [[ -z "$latest" ]]; then
        die "No ARM64 build-tools with aapt2 found in ${bt_dir}.\n  Install build-tools first: $0 install-build-tools <version>"
    fi

    configure_gradle "$latest"
    ok "Gradle configured with aapt2 at: ${latest}"
}

# ── doctor ─────────────────────────────────────────────────────────────────────

cmd_doctor() {
    detect_sdk_root

    header "Android SDK ARM64 - Diagnostic Check"
    echo "  SDK root: $SDK_ROOT"
    echo ""

    local issues=0

    # Architecture
    local arch
    arch="$(uname -m)"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        ok "Architecture: ${arch}"
    else
        err "Architecture: ${arch} — this project only supports aarch64"
        ((issues++))
    fi

    # ANDROID_HOME
    if [[ -n "${ANDROID_HOME:-}" ]]; then
        ok "ANDROID_HOME: ${ANDROID_HOME}"
    else
        warn "ANDROID_HOME not set"
        ((issues++))
    fi

    # Build-tools — check each version independently
    local bt_dir="$SDK_ROOT/build-tools"
    if [[ -d "$bt_dir" ]]; then
        local bt_count=0
        for d in $(ls -d "$bt_dir"/*/ 2>/dev/null | sort -V); do
            local ver
            ver="$(basename "$d")"
            ((bt_count++))

            # Determine arch from aapt2 (or first available binary)
            local arch_label="unknown"
            local probe_bin=""
            for bin in aapt2 aapt aidl zipalign dexdump; do
                if [[ -x "${d}${bin}" ]]; then
                    probe_bin="${d}${bin}"
                    break
                fi
            done
            if [[ -n "$probe_bin" ]]; then
                local ftype
                ftype=$(file -b "$probe_bin" 2>/dev/null)
                if [[ "$ftype" == *"aarch64"* || "$ftype" == *"ARM aarch64"* ]]; then
                    arch_label="arm64"
                elif [[ "$ftype" == *"x86-64"* || "$ftype" == *"x86_64"* ]]; then
                    arch_label="x86_64"
                fi
            fi

            if [[ "$arch_label" == "arm64" ]]; then
                ok "build-tools ${ver}: native ARM64"
                for bin in aapt2 aapt aidl zipalign dexdump; do
                    if [[ -x "${d}${bin}" ]]; then
                        ok "  ${bin}: OK"
                    else
                        warn "  ${bin}: missing"
                        ((issues++))
                    fi
                done
            elif [[ "$arch_label" == "x86_64" ]]; then
                err "build-tools ${ver}: x86_64 (won't run on ARM64!)"
                echo -e "    ${DIM}Replace with: $0 install-build-tools ${ver}${NC}"
                ((issues++))
            else
                warn "build-tools ${ver}: no binaries found"
                ((issues++))
            fi
        done
        if [[ $bt_count -eq 0 ]]; then
            warn "No build-tools installed"
            ((issues++))
        fi
    else
        warn "No build-tools installed"
        ((issues++))
    fi

    # Platform-tools
    local pt_dir="$SDK_ROOT/platform-tools"
    if [[ -d "$pt_dir" ]]; then
        for bin in adb fastboot; do
            local path="$pt_dir/$bin"
            if [[ -x "$path" ]]; then
                local ftype
                ftype=$(file -b "$path" 2>/dev/null)
                if [[ "$ftype" == *"aarch64"* || "$ftype" == *"ARM aarch64"* ]]; then
                    ok "  $bin: native ARM64"
                elif [[ "$ftype" == *"x86_64"* ]]; then
                    err "  $bin: x86_64 (won't run!)"
                    ((issues++))
                else
                    ok "  $bin: present"
                fi
            else
                warn "  $bin: missing"
                ((issues++))
            fi
        done
    else
        warn "platform-tools not found"
        ((issues++))
    fi

    # Platforms
    local platforms_dir="$SDK_ROOT/platforms"
    if [[ -d "$platforms_dir" ]]; then
        local platforms
        platforms=$(ls -d "$platforms_dir"/*/ 2>/dev/null | xargs -I{} basename {} | sort -V | tr '\n' ' ')
        if [[ -n "$platforms" ]]; then
            ok "Platforms: ${platforms}"
        else
            warn "No platforms installed"
            ((issues++))
        fi
    else
        warn "No platforms installed"
        ((issues++))
    fi

    # NDK shims
    local ndk_dir="$SDK_ROOT/ndk"
    if [[ -d "$ndk_dir" ]]; then
        local ndk_versions
        ndk_versions=$(ls -d "$ndk_dir"/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')
        if [[ -n "$ndk_versions" ]]; then
            ok "NDK shims: ${ndk_versions}"
            for ver in $ndk_versions; do
                local strip_shim="$ndk_dir/$ver/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
                if [[ -x "$strip_shim" ]]; then
                    ok "  NDK ${ver}: llvm-strip OK"
                else
                    warn "  NDK ${ver}: llvm-strip missing"
                    ((issues++))
                fi
            done
        fi
    else
        warn "No NDK shims installed"
        ((issues++))
    fi

    # CMake shim
    local cmake_shim="$SDK_ROOT/cmake/3.22.1/bin/cmake"
    if [[ -x "$cmake_shim" ]]; then
        if head -1 "$cmake_shim" 2>/dev/null | grep -q "^#!/bin/sh"; then
            ok "CMake shim: OK"
        else
            local ftype
            ftype=$(file -b "$cmake_shim" 2>/dev/null)
            if [[ "$ftype" == *"x86-64"* ]]; then
                err "CMake 3.22.1: x86_64 binary (needs shim!)"
                ((issues++))
            else
                ok "CMake: present"
            fi
        fi
    else
        info "CMake shim: not installed (only needed if project uses NDK)"
    fi

    # Gradle config
    local gradle_props="$HOME/.gradle/gradle.properties"
    if [[ -f "$gradle_props" ]] && grep -q "^android.aapt2FromMavenOverride=" "$gradle_props"; then
        local aapt2_path
        aapt2_path=$(grep "^android.aapt2FromMavenOverride=" "$gradle_props" | cut -d= -f2)
        if [[ -x "$aapt2_path" ]]; then
            ok "Gradle aapt2 override: $aapt2_path"
        else
            warn "Gradle aapt2 override points to missing file: $aapt2_path"
            ((issues++))
        fi
    else
        warn "Gradle aapt2 override not configured"
        ((issues++))
    fi

    # Java
    if check_command java; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1)
        ok "Java: $java_ver"
    else
        warn "Java not found"
        ((issues++))
    fi

    # Flutter
    if check_command flutter; then
        local flutter_ver
        flutter_ver=$(flutter --version 2>&1 | head -1)
        ok "Flutter: $flutter_ver"
    else
        info "Flutter: not found (optional)"
    fi

    # Summary
    echo ""
    if [[ $issues -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}All checks passed.${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}Found $issues issue(s).${NC} See above."
    fi
    echo ""
}

# ── status ─────────────────────────────────────────────────────────────────────

cmd_status() {
    detect_sdk_root

    header "Android SDK ARM64 - Status"
    echo "  SDK root: $SDK_ROOT"

    # Build-tools
    local bt_dir="$SDK_ROOT/build-tools"
    if [[ -d "$bt_dir" ]]; then
        for d in $(ls -d "$bt_dir"/*/ 2>/dev/null | sort -V); do
            local ver
            ver=$(basename "$d")
            # Check if our ARM64 binaries or x86_64
            local aapt2="$d/aapt2"
            local arch_label="?"
            if [[ -x "$aapt2" ]]; then
                local ftype
                ftype=$(file -b "$aapt2" 2>/dev/null)
                if [[ "$ftype" == *"aarch64"* ]]; then
                    arch_label="arm64"
                elif [[ "$ftype" == *"x86-64"* ]]; then
                    arch_label="x86_64"
                fi
            fi
            echo -e "    ${GREEN}+${NC} build-tools;${ver}  ${DIM}(${arch_label})${NC}"
        done
    fi

    # Platform-tools
    local pt_dir="$SDK_ROOT/platform-tools"
    if [[ -d "$pt_dir" ]] && [[ -x "$pt_dir/adb" ]]; then
        local ftype
        ftype=$(file -b "$pt_dir/adb" 2>/dev/null)
        local arch_label="?"
        [[ "$ftype" == *"aarch64"* ]] && arch_label="arm64"
        [[ "$ftype" == *"x86-64"* ]] && arch_label="x86_64"
        echo -e "    ${GREEN}+${NC} platform-tools  ${DIM}(${arch_label})${NC}"
    fi

    # NDK shims
    local ndk_dir="$SDK_ROOT/ndk"
    if [[ -d "$ndk_dir" ]]; then
        for d in "$ndk_dir"/*/; do
            [[ -d "$d" ]] || continue
            echo -e "    ${GREEN}+${NC} ndk;$(basename "$d")  ${DIM}(shim)${NC}"
        done
    fi

    # CMake shim
    if [[ -d "$SDK_ROOT/cmake" ]]; then
        for d in "$SDK_ROOT/cmake"/*/; do
            [[ -d "$d" ]] || continue
            echo -e "    ${GREEN}+${NC} cmake;$(basename "$d")  ${DIM}(shim)${NC}"
        done
    fi

    # Cmdline-tools
    if [[ -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
        echo -e "    ${GREEN}+${NC} cmdline-tools;latest"
    fi

    # Platforms
    local platforms_dir="$SDK_ROOT/platforms"
    if [[ -d "$platforms_dir" ]]; then
        for d in "$platforms_dir"/*/; do
            [[ -d "$d" ]] || continue
            echo -e "    ${GREEN}+${NC} platforms;$(basename "$d")"
        done
    fi

    echo ""
}

# ── Shared internals ──────────────────────────────────────────────────────────

find_strip() {
    if check_command llvm-strip; then command -v llvm-strip
    elif check_command strip; then command -v strip
    else echo ""; fi
}

find_cmake_bin() {
    if check_command cmake; then command -v cmake
    else echo ""; fi
}

find_ninja_bin() {
    if check_command ninja; then command -v ninja
    elif check_command ninja-build; then command -v ninja-build
    else echo ""; fi
}

create_source_properties() {
    local dir="$1" desc="$2" revision="$3"
    cat > "${dir}/source.properties" << PROPS
Pkg.Desc = ${desc}
Pkg.Revision = ${revision}
PROPS
}

configure_gradle() {
    local aapt2_path="$1"
    local gradle_props="$HOME/.gradle/gradle.properties"

    info "Configuring Gradle aapt2 override..."
    echo "  aapt2:  ${aapt2_path}"
    echo "  config: ${gradle_props}"
    mkdir -p "$(dirname "$gradle_props")"

    if [[ -f "$gradle_props" ]]; then
        sed -i '/^android\.aapt2FromMavenOverride=/d' "$gradle_props"
    fi
    echo "android.aapt2FromMavenOverride=${aapt2_path}" >> "$gradle_props"
    ok "Gradle: ${gradle_props}"
}

create_ndk_shim() {
    local ndk_version="$1"
    local ndk_dir="$SDK_ROOT/ndk/${ndk_version}"

    info "Creating NDK ${ndk_version} shim..."
    echo "  NDK dir:   ${ndk_dir}"

    local strip_bin
    strip_bin="$(find_strip)"
    [[ -z "$strip_bin" ]] && die "No strip or llvm-strip found. Install binutils."

    # llvm-strip shim
    local llvm_strip_dir="${ndk_dir}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    mkdir -p "$llvm_strip_dir"
    cat > "${llvm_strip_dir}/llvm-strip" << SHIM
#!/bin/sh
exec ${strip_bin} "\$@"
SHIM
    chmod +x "${llvm_strip_dir}/llvm-strip"

    # source.properties
    cat > "${ndk_dir}/source.properties" << PROPS
Pkg.Desc = Android NDK
Pkg.Revision = ${ndk_version}
PROPS

    # CMake toolchain shim
    local toolchain_dir="${ndk_dir}/build/cmake"
    mkdir -p "$toolchain_dir"

    local gcc_path
    gcc_path="$(command -v gcc 2>/dev/null || echo /usr/bin/gcc)"
    local gpp_path
    gpp_path="$(command -v g++ 2>/dev/null || echo /usr/bin/g++)"

    cat > "${toolchain_dir}/android.toolchain.cmake" << CMAKE
# NDK toolchain shim — auto-generated by setup.sh
set(CMAKE_C_COMPILER ${gcc_path})
set(CMAKE_CXX_COMPILER ${gpp_path})
CMAKE

    ok "NDK ${ndk_version} shim: llvm-strip -> ${strip_bin}"
}

create_cmake_shim() {
    local cmake_version="$1"
    local cmake_dir="$SDK_ROOT/cmake/${cmake_version}/bin"

    local sys_cmake
    sys_cmake="$(find_cmake_bin)"
    local sys_ninja
    sys_ninja="$(find_ninja_bin)"

    [[ -z "$sys_cmake" ]] && { warn "System cmake not found, skipping cmake shim."; return; }

    info "Creating CMake ${cmake_version} shim..."
    echo "  CMake dir: ${cmake_dir}"
    mkdir -p "$cmake_dir"

    # If there's an existing x86_64 binary, back it up
    if [[ -f "${cmake_dir}/cmake" ]] && ! head -1 "${cmake_dir}/cmake" 2>/dev/null | grep -q "^#!/bin/sh"; then
        mv "${cmake_dir}/cmake" "${cmake_dir}/cmake.x86_64.bak" 2>/dev/null || true
    fi
    if [[ -f "${cmake_dir}/ninja" ]] && ! head -1 "${cmake_dir}/ninja" 2>/dev/null | grep -q "^#!/bin/sh"; then
        mv "${cmake_dir}/ninja" "${cmake_dir}/ninja.x86_64.bak" 2>/dev/null || true
    fi

    cat > "${cmake_dir}/cmake" << SHIM
#!/bin/sh
# CMake shim — filters Android flags, delegates to system cmake.
# Auto-generated by ${REPO_NAME}/setup.sh
FILTERED_ARGS=""
for arg in "\$@"; do
    case "\$arg" in
        -DCMAKE_SYSTEM_NAME=Android) ;;
        -DCMAKE_SYSTEM_VERSION=*) ;;
        -DANDROID_PLATFORM=*) ;;
        -DANDROID_ABI=*) ;;
        -DCMAKE_ANDROID_ARCH_ABI=*) ;;
        -DANDROID_NDK=*) ;;
        -DCMAKE_ANDROID_NDK=*) ;;
        -DCMAKE_TOOLCHAIN_FILE=*) ;;
        *) FILTERED_ARGS="\$FILTERED_ARGS \$arg" ;;
    esac
done
exec ${sys_cmake} \$FILTERED_ARGS
SHIM
    chmod +x "${cmake_dir}/cmake"

    if [[ -n "$sys_ninja" ]]; then
        cat > "${cmake_dir}/ninja" << SHIM
#!/bin/sh
exec ${sys_ninja} "\$@"
SHIM
        chmod +x "${cmake_dir}/ninja"
    fi

    ok "CMake ${cmake_version} shim -> ${sys_cmake}"
}

ensure_cmdline_tools() {
    local cmdline_dir="$SDK_ROOT/cmdline-tools/latest"
    if [[ -x "${cmdline_dir}/bin/sdkmanager" ]]; then return 0; fi

    info "Installing Android command-line tools..."
    require_command curl
    require_command unzip
    check_command java || die "Java required for sdkmanager. Install JDK 17+."

    local tmpdir
    tmpdir="$(mktemp -d)"

    curl -fSL -o "${tmpdir}/cmdline-tools.zip" "$CMDLINE_TOOLS_URL" 2>/dev/null \
        || die "Failed to download command-line tools."
    unzip -q "${tmpdir}/cmdline-tools.zip" -d "${tmpdir}" \
        || die "Failed to extract command-line tools."

    mkdir -p "$SDK_ROOT/cmdline-tools"
    rm -rf "$cmdline_dir"
    mv "${tmpdir}/cmdline-tools" "$cmdline_dir"
    rm -rf "$tmpdir"

    ok "Command-line tools installed."
}

run_sdkmanager() {
    local sdkmanager="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
    [[ -x "$sdkmanager" ]] || die "sdkmanager not found. Run: $0 install-cmd-tools"
    "$sdkmanager" --sdk_root="$SDK_ROOT" "$@"
}

accept_licenses() {
    yes 2>/dev/null | run_sdkmanager --licenses >/dev/null 2>&1 || true
}

# Download a release tarball and install binaries
download_and_install_release() {
    local release_tag="$1"
    local dest_dir="$2"
    local component="$3"  # "build-tools" or "platform-tools"

    require_command curl
    require_command tar

    local version="${release_tag#v}"

    # Try component-specific tarball first, then combined tarball
    local tarballs=(
        "${REPO_NAME}-${component}-${version}.tar.gz"
        "${REPO_NAME}-${release_tag}.tar.gz"
    )

    local tmpdir
    tmpdir="$(mktemp -d)"
    local downloaded=""

    for tarball in "${tarballs[@]}"; do
        local url="https://github.com/${REPO}/releases/download/${release_tag}/${tarball}"
        info "Trying ${tarball}..."
        if curl -fSL --progress-bar -o "$tmpdir/$tarball" "$url" 2>/dev/null; then
            downloaded="$tarball"
            break
        fi
    done

    if [[ -z "$downloaded" ]]; then
        rm -rf "$tmpdir"
        die "Download failed. Check: ${REPO_URL}/releases/tag/${release_tag}"
    fi

    info "Extracting ${downloaded}..."
    tar -xzf "$tmpdir/$downloaded" -C "$tmpdir"

    mkdir -p "$dest_dir"
    info "Installing binaries to: ${BOLD}${dest_dir}${NC}"

    local bins_ref
    if [[ "$component" == "build-tools" ]]; then
        bins_ref=("${BUILD_TOOLS_BINS[@]}")
    else
        bins_ref=("${PLATFORM_TOOLS_BINS[@]}")
    fi

    local installed=0
    for bin in "${bins_ref[@]}"; do
        # Look for binary in extracted tree
        local src=""
        for candidate in \
            "$tmpdir/${component}/$bin" \
            "$tmpdir/bin/$bin" \
            "$tmpdir/$bin" \
            "$tmpdir"/*/"$bin"; do
            if [[ -f "$candidate" ]]; then
                src="$candidate"
                break
            fi
        done
        if [[ -n "$src" ]]; then
            cp "$src" "$dest_dir/$bin"
            chmod +x "$dest_dir/$bin"
            ((installed++))
            echo -e "    ${GREEN}+${NC} $bin"
        else
            echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not found in tarball)${NC}"
        fi
    done

    rm -rf "$tmpdir"
    ok "Installed ${installed} binaries."
}

# Build tools from AOSP source
build_tools_from_source() {
    local component="$1"  # "build-tools" or "platform-tools"
    local version="$2"

    header "Building ${component} ${version} from source"

    # Check build dependencies
    info "Checking build dependencies..."
    local missing=()
    for cmd in gcc g++ cmake ninja git python3 go bison flex; do
        check_command "$cmd" || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing: ${missing[*]}"
        echo ""
        if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
            echo "  sudo dnf install $DEPS_FEDORA"
        elif [[ -f /etc/debian_version ]]; then
            echo "  sudo apt install $DEPS_DEBIAN"
        fi
        die "Install dependencies and retry."
    fi
    ok "Dependencies OK."

    # Find AOSP tag
    local aosp_tag
    aosp_tag="$(get_aosp_tag "$component" "$version" 2>/dev/null || echo "")"
    if [[ -z "$aosp_tag" ]]; then
        # Fallback: try platform-tools-<version>
        aosp_tag="platform-tools-${version}"
        warn "No AOSP tag in versions.json, trying: ${aosp_tag}"
    fi

    # Determine source directory
    resolve_script_dir
    local build_dir="$SCRIPT_DIR"

    if [[ ! -f "${build_dir}/repos.json" ]] || [[ ! -f "${build_dir}/build.py" ]]; then
        # Clone the repo
        build_dir="$(mktemp -d)/${REPO_NAME}"
        info "Cloning build system..."
        git clone --depth 1 "$REPO_URL" "$build_dir" \
            || die "Failed to clone repository."
    fi

    local versioned_build="${build_dir}/build/${component}-${version}"

    echo ""
    echo "  AOSP tag:    ${aosp_tag}"
    echo "  Source dir:  ${build_dir}/src/ (~2-4 GB)"
    echo "  Build dir:   ${versioned_build}/"
    echo "  Output:      ${versioned_build}/bin/ (flat)"
    echo ""

    # Clone AOSP sources
    info "Cloning AOSP sources (tag: ${aosp_tag})..."
    python3 "${build_dir}/get_source.py" --tags "$aosp_tag" \
        --component "$component" --version "$version"

    # Build protoc
    local protoc_path="${build_dir}/src/protobuf/build/protoc"
    if [[ ! -x "$protoc_path" ]]; then
        info "Building host protoc..."
        mkdir -p "${build_dir}/src/protobuf/build"

        # Copy config.h — try version-specific, then base
        local config_src=""
        for candidate in \
            "${build_dir}/patches/${component}/${version}/misc/protobuf_config.h" \
            "${build_dir}/patches/base/misc/protobuf_config.h"; do
            if [[ -f "$candidate" ]]; then
                config_src="$candidate"
                break
            fi
        done
        if [[ -n "$config_src" ]]; then
            cp "$config_src" "${build_dir}/src/protobuf/build/config.h"
        fi

        cmake -GNinja \
            -B "${build_dir}/src/protobuf/build" \
            -S "${build_dir}/src/protobuf" \
            -Dprotobuf_BUILD_TESTS=OFF \
            || die "protoc cmake failed."

        ninja -C "${build_dir}/src/protobuf/build" -j"$(nproc)" protoc \
            || die "protoc build failed."
        ok "protoc built."
    fi

    # Build all tools
    info "Building SDK tools..."
    python3 "${build_dir}/build.py" \
        --protoc="$protoc_path" \
        --build="$versioned_build" \
        || die "Build failed."

    # Install binaries
    local build_bin="${versioned_build}/bin"
    [[ -d "$build_bin" ]] || die "Build output not found at ${build_bin}"

    if [[ "$component" == "build-tools" ]]; then
        local dest="$SDK_ROOT/build-tools/${version}"
        mkdir -p "$dest"
        info "Copying build-tools binaries to: ${BOLD}${dest}${NC}"
        for bin in "${BUILD_TOOLS_BINS[@]}"; do
            if [[ -f "${build_bin}/${bin}" ]]; then
                cp "${build_bin}/${bin}" "$dest/" && chmod +x "$dest/$bin"
                echo -e "    ${GREEN}+${NC} $bin"
            else
                echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not built)${NC}"
            fi
        done
        ok "build-tools installed to ${dest}"
    else
        local dest="$SDK_ROOT/platform-tools"
        mkdir -p "$dest"
        info "Copying platform-tools binaries to: ${BOLD}${dest}${NC}"
        for bin in "${PLATFORM_TOOLS_BINS[@]}"; do
            if [[ -f "${build_bin}/${bin}" ]]; then
                cp "${build_bin}/${bin}" "$dest/" && chmod +x "$dest/$bin"
                echo -e "    ${GREEN}+${NC} $bin"
            else
                echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not built)${NC}"
            fi
        done
        ok "platform-tools installed to ${dest}"
    fi
}

# ── NDK version detection ─────────────────────────────────────────────────────

detect_ndk_version() {
    local project_dir="${1:-.}"
    local build_gradle=""

    for f in \
        "${project_dir}/android/app/build.gradle" \
        "${project_dir}/android/app/build.gradle.kts"; do
        [[ -f "$f" ]] && build_gradle="$f" && break
    done
    [[ -z "$build_gradle" ]] && return 1

    local version
    version=$(grep -oP 'ndkVersion\s*[=: ]\s*"?\K[0-9]+\.[0-9]+\.[0-9]+' "$build_gradle" 2>/dev/null \
        || grep -oP "flutter\.ndkVersion" "$build_gradle" 2>/dev/null \
        || echo "")

    if [[ "$version" == "flutter.ndkVersion" ]]; then
        local flutter_sdk=""
        if [[ -n "${FLUTTER_ROOT:-}" ]]; then
            flutter_sdk="$FLUTTER_ROOT"
        elif check_command flutter; then
            flutter_sdk="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
        fi
        if [[ -n "$flutter_sdk" ]]; then
            for f in \
                "${flutter_sdk}/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" \
                "${flutter_sdk}/packages/flutter_tools/gradle/flutter.groovy"; do
                if [[ -f "$f" ]]; then
                    local found
                    found=$(grep -oP 'ndkVersion[^=]*=\s*"?\K[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null || echo "")
                    [[ -n "$found" ]] && version="$found" && break
                fi
            done
        fi
    fi

    [[ -n "$version" && "$version" != "flutter.ndkVersion" ]] && echo "$version" && return 0
    return 1
}

# ── help ───────────────────────────────────────────────────────────────────────

cmd_help() {
    cat << 'BANNER'

  Android SDK Tools for Linux ARM64
  ==================================

BANNER

    echo -e "  ${BOLD}INSTALL COMMANDS${NC}"
    echo ""
    echo "    install-build-tools <version>     Install build-tools (aapt2, aapt, aidl, ...)"
    echo "    install-platform-tools <version>  Install platform-tools (adb, fastboot, ...)"
    echo "    install-ndk <version>             Create NDK shim (llvm-strip)"
    echo "    install-cmake [version]           Create CMake shim (default: 3.22.1)"
    echo "    install-cmd-tools                 Install sdkmanager"
    echo "    install-platforms [packages]      Install Android platforms"
    echo ""
    echo -e "  ${BOLD}BUILD COMMANDS${NC} ${DIM}(for unverified versions)${NC}"
    echo ""
    echo "    build-build-tools <version>       Build build-tools from AOSP source"
    echo "    build-platform-tools <version>    Build platform-tools from AOSP source"
    echo ""
    echo -e "  ${BOLD}INFO COMMANDS${NC}"
    echo ""
    echo "    list-versions                     Show all available versions"
    echo "    status                            Show what's installed"
    echo "    doctor                            Diagnose setup issues"
    echo "    setup-gradle                      Configure Gradle aapt2 override"
    echo ""
    echo -e "  ${BOLD}OPTIONS${NC}"
    echo ""
    echo "    --sdk-root <path>    Override Android SDK directory"
    echo ""
    echo -e "  ${BOLD}SDK ROOT DETECTION${NC} ${DIM}(in priority order)${NC}"
    echo ""
    echo "    1. --sdk-root <path>        (if passed)"
    echo "    2. \$ANDROID_HOME            (if set)"
    echo "    3. \$ANDROID_SDK_ROOT        (if set)"
    echo "    4. ~/Android/Sdk            (if exists)"
    echo "    5. ~/android-sdk            (default, created if needed)"
    echo ""
    echo -e "  ${BOLD}QUICK START${NC}"
    echo ""
    echo "    ./setup.sh install-build-tools 35.0.2"
    echo "    ./setup.sh install-platform-tools 35.0.2"
    echo "    ./setup.sh install-ndk 28.2.13676358"
    echo "    ./setup.sh install-cmake"
    echo "    ./setup.sh install-cmd-tools"
    echo "    ./setup.sh install-platforms android-35"
    echo "    ./setup.sh doctor"
    echo ""
    echo -e "  ${BOLD}REPO${NC}  ${REPO_URL}"
    echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
    if [[ $# -eq 0 ]]; then
        cmd_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        list-versions)          cmd_list_versions "$@" ;;
        install-build-tools)    cmd_install_build_tools "$@" ;;
        install-platform-tools) cmd_install_platform_tools "$@" ;;
        install-ndk)            cmd_install_ndk "$@" ;;
        install-cmake)          cmd_install_cmake "$@" ;;
        install-cmd-tools)      cmd_install_cmd_tools "$@" ;;
        install-platforms)      cmd_install_platforms "$@" ;;
        build-build-tools)      cmd_build_build_tools "$@" ;;
        build-platform-tools)   cmd_build_platform_tools "$@" ;;
        setup-gradle)           cmd_setup_gradle "$@" ;;
        doctor)                 cmd_doctor "$@" ;;
        status)                 cmd_status "$@" ;;
        help|--help|-h)         cmd_help ;;
        *)
            err "Unknown command: $command"
            echo "  Run '$0 help' for usage."
            exit 1
            ;;
    esac
}

main "$@"
