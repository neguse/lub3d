# Building

## Prerequisites

- CMake 3.20+
- C/C++ compiler (MSVC, Clang, GCC)
- Ninja (recommended)
- Python 3 (for code generation)

## Quick Start

```bash
# Clone with submodules
git clone --recursive https://github.com/neguse/mane3d.git
cd mane3d

# Configure and build
cmake --preset win-d3d11-debug
cmake --build --preset win-d3d11-debug

# Run example
./build/win-d3d11-debug/mane3d-example.exe examples/breakout.lua
```

## CMake Presets

| Preset                | Platform | Backend | Type    |
| --------------------- | -------- | ------- | ------- |
| `win-d3d11-debug`     | Windows  | D3D11   | Debug   |
| `win-d3d11-release`   | Windows  | D3D11   | Release |
| `macos-metal-release` | macOS    | Metal   | Release |
| `linux-gl-debug`      | Linux    | OpenGL  | Debug   |
| `wasm-release`        | Web      | WebGPU  | Release |

## CMake Options

| Option                  | Default | Description                                     |
| ----------------------- | ------- | ----------------------------------------------- |
| `MANE3D_BUILD_EXAMPLE`  | ON      | Build example executable                        |
| `MANE3D_BUILD_SHDC`     | ON      | Build sokol-shdc for runtime shader compilation |
| `MANE3D_BUILD_SHARED`   | OFF     | Build as shared library                         |
| `MANE3D_BUILD_IMGUI`    | ON      | Build Dear ImGui integration                    |
| `MANE3D_BUILD_BC7ENC`   | ON      | Build BC7 encoder library                       |
| `MANE3D_USE_SYSTEM_LUA` | OFF     | Use system Lua instead of bundled               |

## Backends

Auto-selected per platform:

- **Windows**: D3D11
- **macOS**: Metal
- **Linux**: OpenGL
- **Web (WASM)**: WebGPU

Override with `MANE3D_BACKEND_*` options.

## WASM Build

```bash
# Setup Emscripten
source ~/emsdk/emsdk_env.sh

# Configure and build
emcmake cmake --preset wasm-release
cmake --build --preset wasm-release
```

## sccache (Build Acceleration)

The build system auto-detects [sccache](https://github.com/mozilla/sccache) for faster incremental builds.

### Windows Setup

Set `VSLANG=1033` to ensure Ninja can filter `/showIncludes` output:

```powershell
# System environment variable (requires restart)
[Environment]::SetEnvironmentVariable("VSLANG", "1033", "Machine")
```

### Verify

After CMake configuration, you should see:

```
-- Using compiler cache: /path/to/sccache
```

## Lua Linting

```bash
# Windows
check.bat

# Linux/macOS
./check.sh
```

Requires lua-language-server.
