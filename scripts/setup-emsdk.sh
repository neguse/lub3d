#!/bin/bash
# Setup Emscripten SDK for WASM builds
# Usage: ./scripts/setup-emsdk.sh

set -e

EMSDK_VERSION="${EMSDK_VERSION:-latest}"
EMSDK_DIR="${EMSDK_DIR:-$HOME/.emsdk}"

if [ -d "$EMSDK_DIR" ]; then
    echo "emsdk already exists at $EMSDK_DIR"
    echo "To reinstall, remove it first: rm -rf $EMSDK_DIR"
else
    echo "Cloning emsdk to $EMSDK_DIR..."
    git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
fi

cd "$EMSDK_DIR"

echo "Installing emsdk $EMSDK_VERSION..."
./emsdk install "$EMSDK_VERSION"

echo "Activating emsdk $EMSDK_VERSION..."
./emsdk activate "$EMSDK_VERSION"

echo ""
echo "Done! To use Emscripten, run:"
echo "  source $EMSDK_DIR/emsdk_env.sh"
echo ""
echo "Or add to your ~/.bashrc:"
echo "  source $EMSDK_DIR/emsdk_env.sh"
