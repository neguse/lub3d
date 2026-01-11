#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Build started"

# Install cmake (download pre-built binary since sudo is not available in CI)
if command -v cmake &> /dev/null; then
    log "cmake already available: $(cmake --version | head -1)"
else
    log "Installing cmake..."
    CMAKE_VERSION="3.28.1"
    curl -sL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" | tar xz
    export PATH="$(pwd)/cmake-${CMAKE_VERSION}-linux-x86_64/bin:$PATH"
    log "cmake installed: $(cmake --version | head -1)"
fi

# Install ninja (download pre-built binary since sudo is not available in CI)
if command -v ninja &> /dev/null; then
    log "ninja already available: $(ninja --version)"
else
    log "Installing ninja..."
    NINJA_VERSION="1.12.1"
    curl -sL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" -o ninja-linux.zip
    unzip -q ninja-linux.zip -d ninja-bin
    export PATH="$(pwd)/ninja-bin:$PATH"
    rm ninja-linux.zip
    log "ninja installed: $(ninja --version)"
fi

# Setup Emscripten SDK
log "Cloning emsdk..."
git clone https://github.com/emscripten-core/emsdk.git
log "Installing emsdk..."
cd emsdk
./emsdk install latest
log "Activating emsdk..."
./emsdk activate latest
source ./emsdk_env.sh
cd ..
log "Emscripten setup complete"

# Build WASM
log "Configuring WASM build..."
emcmake cmake -G Ninja -B build/wasm-release -DCMAKE_BUILD_TYPE=Release
log "Building WASM..."
cmake --build build/wasm-release
log "WASM build complete"

# Build Playground (Vite)
log "Installing npm dependencies..."
cd playground
npm install
log "Building Vite project..."
npm run build
cd ..
log "Playground build complete"

# Copy to dist/
log "Copying to dist/..."
mkdir -p dist
cp -r playground/dist/* dist/
cp build/wasm-release/*.wasm dist/
cp build/wasm-release/*.js dist/

log "Build finished"
