#!/usr/bin/env bash
#
# setup.sh - Install Android SDK tools for Linux ARM64
#
# Downloads pre-built ARM64 binaries from GitHub Releases and configures
# the Android SDK for Flutter development on Linux ARM64 (e.g. Asahi Linux).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/anthropics/android-sdk-linux-arm64/main/setup.sh | bash
#   # or
#   ./setup.sh [--sdk-root /path/to/android-sdk] [--version 35.0.2]
#
# What this script does:
#   1. Downloads pre-built ARM64 binaries from GitHub Releases
#   2. Installs build-tools (aapt2, aapt, aidl, zipalign, dexdump, etc.)
#   3. Installs platform-tools (adb, fastboot, etc.)
#   4. Configures gradle.properties for aapt2 override
#   5. Creates NDK shim so Flutter can find llvm-strip
#
set -euo pipefail

# ── Configuration ──

REPO="anthropics/android-sdk-linux-arm64"
VERSION="${ANDROID_SDK_TOOLS_VERSION:-35.0.2}"
BUILD_TOOLS_VERSION="35.0.2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Parse arguments ──

SDK_ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sdk-root)  SDK_ROOT="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--sdk-root PATH] [--version VERSION]"
            echo ""
            echo "Options:"
            echo "  --sdk-root PATH   Android SDK root directory (default: auto-detect)"
            echo "  --version VERSION  Tool version to install (default: $VERSION)"
            echo ""
            echo "Environment variables:"
            echo "  ANDROID_HOME / ANDROID_SDK_ROOT   Android SDK path"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

# ── Detect Android SDK root ──

if [[ -z "$SDK_ROOT" ]]; then
    if [[ -n "${ANDROID_HOME:-}" ]]; then
        SDK_ROOT="$ANDROID_HOME"
    elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        SDK_ROOT="$ANDROID_SDK_ROOT"
    elif [[ -d "$HOME/Android/Sdk" ]]; then
        SDK_ROOT="$HOME/Android/Sdk"
    elif [[ -d "$HOME/android-sdk" ]]; then
        SDK_ROOT="$HOME/android-sdk"
    else
        echo ""
        echo -e "${BOLD}Where is your Android SDK installed?${NC}"
        echo ""
        echo "  Common locations:"
        echo "    $HOME/Android/Sdk"
        echo "    $HOME/android-sdk"
        echo ""
        read -rp "Android SDK root: " SDK_ROOT
        SDK_ROOT="${SDK_ROOT/#\~/$HOME}"
    fi
fi

if [[ -z "$SDK_ROOT" ]]; then
    error "No SDK root specified. Set ANDROID_HOME or use --sdk-root."
fi

# Create SDK root if it doesn't exist
mkdir -p "$SDK_ROOT"
SDK_ROOT="$(cd "$SDK_ROOT" && pwd)"

info "Android SDK root: $SDK_ROOT"
info "Tools version: $VERSION"
echo ""

# ── Check prerequisites ──

check_command() {
    if ! command -v "$1" &>/dev/null; then
        error "Required command '$1' not found. Please install it."
    fi
}

check_command curl
check_command tar

# Verify we're on Linux ARM64
ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    warn "This script installs ARM64 binaries, but your architecture is: $ARCH"
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy] ]] || exit 1
fi

# ── Download release ──

RELEASE_TAG="v${VERSION}"
TARBALL="android-sdk-tools-linux-arm64-${VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${TARBALL}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading ${TARBALL}..."
if ! curl -fSL -o "$TMPDIR/$TARBALL" "$DOWNLOAD_URL" 2>/dev/null; then
    error "Download failed. Check that release ${RELEASE_TAG} exists at:\n  https://github.com/${REPO}/releases"
fi
ok "Downloaded."

info "Extracting..."
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
ok "Extracted."

# ── Install build-tools ──

BT_DIR="$SDK_ROOT/build-tools/${BUILD_TOOLS_VERSION}"
info "Installing build-tools to $BT_DIR"
mkdir -p "$BT_DIR"

# Build-tools binaries
for bin in aapt aapt2 aidl zipalign dexdump split-select; do
    src="$TMPDIR/bin/$bin"
    if [[ -f "$src" ]]; then
        cp "$src" "$BT_DIR/$bin"
        chmod +x "$BT_DIR/$bin"
    else
        warn "Binary not found: $bin"
    fi
done

# Some build-tools also need dx/d8 wrappers - these are Java-based and
# should already exist from sdkmanager. We only replace native binaries.
ok "build-tools installed."

# ── Install platform-tools ──

PT_DIR="$SDK_ROOT/platform-tools"
info "Installing platform-tools to $PT_DIR"
mkdir -p "$PT_DIR"

for bin in adb fastboot sqlite3 etc1tool hprof-conv mke2fs e2fsdroid make_f2fs make_f2fs_casefold sload_f2fs; do
    src="$TMPDIR/bin/$bin"
    if [[ -f "$src" ]]; then
        cp "$src" "$PT_DIR/$bin"
        chmod +x "$PT_DIR/$bin"
    else
        warn "Binary not found: $bin"
    fi
done
ok "platform-tools installed."

# ── Configure gradle.properties for aapt2 override ──

GRADLE_PROPS="$HOME/.gradle/gradle.properties"
AAPT2_PATH="$BT_DIR/aapt2"

info "Configuring gradle.properties..."
mkdir -p "$(dirname "$GRADLE_PROPS")"

AAPT2_PROP="android.aapt2FromMavenOverride=${AAPT2_PATH}"

if [[ -f "$GRADLE_PROPS" ]]; then
    # Remove any existing aapt2 override line
    if grep -q "^android.aapt2FromMavenOverride=" "$GRADLE_PROPS" 2>/dev/null; then
        sed -i '/^android\.aapt2FromMavenOverride=/d' "$GRADLE_PROPS"
    fi
fi

echo "$AAPT2_PROP" >> "$GRADLE_PROPS"
ok "Added aapt2 override to $GRADLE_PROPS"

# ── Create NDK shim for llvm-strip ──

# Flutter requires NDK for llvm-strip during APK builds.
# Instead of downloading the full NDK (~1GB, x86_64-only), we create a
# shim directory that points to the system's llvm-strip or strip.

info "Setting up NDK shim for llvm-strip..."

# Find system llvm-strip or strip
STRIP_BIN=""
if command -v llvm-strip &>/dev/null; then
    STRIP_BIN="$(command -v llvm-strip)"
elif command -v strip &>/dev/null; then
    STRIP_BIN="$(command -v strip)"
fi

if [[ -n "$STRIP_BIN" ]]; then
    # Find the NDK version Flutter expects, or create a minimal one
    # Flutter looks for: ndk/<version>/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
    NDK_VERSION="27.0.12077973"  # Common default Flutter expects
    NDK_BIN_DIR="$SDK_ROOT/ndk/${NDK_VERSION}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    mkdir -p "$NDK_BIN_DIR"

    # Create symlink
    ln -sf "$STRIP_BIN" "$NDK_BIN_DIR/llvm-strip"

    # Also create a source.properties so sdkmanager recognizes it
    NDK_PROPS="$SDK_ROOT/ndk/${NDK_VERSION}/source.properties"
    if [[ ! -f "$NDK_PROPS" ]]; then
        cat > "$NDK_PROPS" << PROPS
Pkg.Desc = Android NDK (shim for ARM64)
Pkg.Revision = ${NDK_VERSION}
PROPS
    fi

    ok "NDK shim created: llvm-strip -> $STRIP_BIN"
else
    warn "Neither llvm-strip nor strip found. NDK shim not created."
    warn "Flutter NDK builds may fail. Install llvm or binutils."
fi

# ── Summary ──

echo ""
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo "  Android SDK root:   $SDK_ROOT"
echo "  build-tools:        $BT_DIR"
echo "  platform-tools:     $PT_DIR"
echo "  aapt2 override:     $GRADLE_PROPS"
echo ""
echo "  Installed binaries:"
for bin in aapt2 aapt aidl zipalign dexdump adb fastboot; do
    path=""
    if [[ -x "$BT_DIR/$bin" ]]; then
        path="$BT_DIR/$bin"
    elif [[ -x "$PT_DIR/$bin" ]]; then
        path="$PT_DIR/$bin"
    fi
    if [[ -n "$path" ]]; then
        ver=$("$path" version 2>&1 | head -1 || "$path" --version 2>&1 | head -1 || echo "installed")
        echo "    $bin: $ver"
    fi
done
echo ""

# Check ANDROID_HOME
if [[ -z "${ANDROID_HOME:-}" ]] || [[ "$ANDROID_HOME" != "$SDK_ROOT" ]]; then
    echo -e "${YELLOW}Tip:${NC} Make sure your shell exports:"
    echo ""
    echo "  export ANDROID_HOME=\"$SDK_ROOT\""
    echo "  export PATH=\"\$ANDROID_HOME/platform-tools:\$PATH\""
    echo ""
fi

echo "You can now build Flutter APKs on Linux ARM64!"
