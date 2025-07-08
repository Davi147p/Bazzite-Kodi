#!/bin/bash
set -euo pipefail

# Configuration
KODI_VERSION="testing"
KODI_REPO="https://github.com/Blahkaey/xbmc"
BUILD_DIR="/tmp/kodi-build"
SOURCE_DIR="/tmp/kodi-source"

# Setup ccache
setup_ccache() {
    echo "[INFO] Setting up ccache..."

    # Create ccache wrapper directory if it doesn't exist
    mkdir -p /usr/lib64/ccache

    # Create symbolic links for compilers
    for compiler in gcc g++ cc c++; do
        ln -sf /usr/bin/ccache /usr/lib64/ccache/${compiler}
    done

    # Configure ccache
    ccache --set-config=max_size=5G
    ccache --set-config=compression=true
    ccache --set-config=compression_level=6
    ccache --set-config=hardlink=true
    ccache --set-config=sloppiness=file_macro,locale,time_macros
    ccache --set-config=hash_dir=false

    # Show initial stats
    echo "[INFO] Initial ccache stats:"
    ccache -s
}

# Call setup at the beginning
setup_ccache

echo "[INFO] Building Kodi ${KODI_VERSION}..."

# Clone source
echo "[INFO] Cloning Kodi repository from ${KODI_VERSION}..."
git clone --depth=1 --branch="${KODI_VERSION}" "${KODI_REPO}" "${SOURCE_DIR}"

# Create build directory
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Configure with ccache
echo "[INFO] Configuring build with ccache..."
cmake "${SOURCE_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCORE_PLATFORM_NAME=gbm \
    -DAPP_RENDER_SYSTEM=gles \
    -DENABLE_VAAPI=ON \
    -DENABLE_VDPAU=OFF \
    -DENABLE_INTERNAL_FMT=ON \
    -DENABLE_INTERNAL_SPDLOG=ON \
    -DENABLE_INTERNAL_FLATBUFFERS=ON \
    -DENABLE_INTERNAL_CROSSGUID=ON \
    -DENABLE_INTERNAL_FSTRCMP=ON \
    -DENABLE_INTERNAL_FFMPEG=ON \
    -DENABLE_INTERNAL_DAV1D=ON \
    -DENABLE_UDEV=ON \
    -DCMAKE_C_FLAGS="-O2 -pipe" \
    -DCMAKE_CXX_FLAGS="-O2 -pipe"

# Build
echo "[INFO] Building Kodi (this will take a while)..."
make -j$(nproc)

# Show ccache stats after main build
echo "[INFO] ccache stats after main build:"
ccache -s

# Install
echo "[INFO] Installing Kodi..."
make install

# Build addons with ccache
echo "[INFO] Building peripheral.joystick addon..."
cd "${SOURCE_DIR}"
CC="ccache gcc" CXX="ccache g++" \
    make -j$(nproc) -C tools/depends/target/binary-addons PREFIX=/usr ADDONS="peripheral.joystick inputstream.adaptive"

# Final ccache stats
echo "[INFO] Final ccache statistics:"
ccache -s

# Update library cache
ldconfig

# Cleanup build files
cd /
rm -rf "${BUILD_DIR}" "${SOURCE_DIR}"

# Verify installation
if [[ ! -x "/usr/lib64/kodi/kodi-gbm" ]]; then
    echo "[ERROR] Kodi binary not found after installation!"
    exit 1
fi

echo "[INFO] Kodi built and installed successfully"
