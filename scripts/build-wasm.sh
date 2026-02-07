#!/bin/bash
# Build lub3d for WebAssembly with WebGPU
# Usage: ./scripts/build-wasm.sh [Release|Debug]

set -e

BUILD_TYPE="${1:-Release}"
EMSDK_DIR="${EMSDK_DIR:-$HOME/.emsdk}"
BUILD_DIR="build/wasm"

# Source emsdk environment
if [ -f "$EMSDK_DIR/emsdk_env.sh" ]; then
    source "$EMSDK_DIR/emsdk_env.sh"
else
    echo "Error: emsdk not found at $EMSDK_DIR"
    echo "Run: ./scripts/setup-emsdk.sh"
    exit 1
fi

# Verify emcc is available
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc not found in PATH"
    exit 1
fi

echo "Using Emscripten: $(emcc --version | head -1)"

# Configure
echo "Configuring ($BUILD_TYPE)..."
emcmake cmake -B "$BUILD_DIR" -S . \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DLUB3D_BUILD_EXAMPLE=ON \
    -DLUB3D_BUILD_SHDC=ON

# Build
echo "Building..."
cmake --build "$BUILD_DIR" --parallel

echo ""
echo "Build complete!"
echo "Output: $BUILD_DIR/lub3d-example.html"
echo ""
echo "To test locally:"
echo "  cd $BUILD_DIR && python3 -m http.server 8080"
echo "  Open: http://localhost:8080/lub3d-example.html"
