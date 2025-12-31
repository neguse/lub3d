# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Måne3D is a lightweight game framework for Lua 5.5 built on top of the Sokol graphics ecosystem.

- Thin Lua wrappers over Sokol libraries (auto-generated bindings)
- Runtime shader compilation via sokol-shdc
- GLM-like math library (lib/glm.lua)

## Build Commands

```bash
# Configure with CMake presets (see CMakePresets.json for available presets)
cmake --preset win-d3d11-debug       # Windows Debug with D3D11
cmake --preset win-d3d11-release     # Windows Release with D3D11
cmake --preset macos-metal-release   # macOS with Metal
cmake --preset linux-gl-debug        # Linux with OpenGL

# Build
cmake --build --preset <preset-name>

# Lint Lua code
check.bat     # Windows (requires lua-language-server in VS Code)
./check.sh    # Linux/macOS
```

### CMake Options

- `MANE3D_BUILD_EXAMPLE` - Build example executable (default: OFF)
- `MANE3D_BUILD_SHDC` - Build sokol-shdc for runtime shader compilation (default: OFF)
- `MANE3D_BUILD_SHARED` - Build as shared library (default: OFF)
- `MANE3D_USE_SYSTEM_LUA` - Use system Lua instead of bundled (default: OFF)

## Architecture

### Directory Structure

- `lib/` - Lua libraries
  - `glm.lua` - Math library (vec2/vec3/vec4/mat4) with LuaCATS annotations
- `gen/` - Generated files (gitignored)
  - `bindings/` - Lua binding C implementations
  - `types/` - Lua type definitions for IDE autocomplete
  - `licenses.c` - Third-party license data
- `src/` - Manual source files
  - `sokol_impl.c` - Sokol implementations
  - `shdc_wrapper.cc` - sokol-shdc C++ wrapper
  - `shdc_lua.c` - Lua bindings for shader compiler
- `examples/` - Sample applications
- `deps/` - Git submodules
  - `lua/` - Lua 5.5 source
  - `sokol/` - Sokol headers and bindgen tools
  - `sokol-tools/` - sokol-shdc shader compiler source

### Code Generation

`gen_lua.py` generates Lua bindings from Sokol headers:
- Uses sokol/bindgen to parse headers
- Generates C modules in `gen/bindings/sokol_*.c`
- Generates Lua type stubs in `gen/types/sokol/*.lua`

`gen_licenses.py` generates `gen/licenses.c` from LICENSE files in deps/.

### Sokol Modules

- `sokol.gfx` - Graphics/rendering
- `sokol.app` - Window and event handling
- `sokol.gl` - Immediate-mode graphics
- `sokol.audio` - Audio playback
- `sokol.time` - Timing utilities
- `sokol.debugtext` - Debug text rendering
- `sokol.log` - Logging
- `sokol.shape` - Shape generation
- `mane3d.licenses` - Third-party license info
- `shdc` - Runtime shader compiler (when MANE3D_BUILD_SHDC=ON)

### Event Loop Model

Lua scripts implement callbacks:

- `init()` - One-time initialization
- `frame()` - Per-frame rendering
- `event(ev)` - Input/window events
- `cleanup()` - Shutdown

### Shader Compilation

Runtime shader compilation via sokol-shdc (requires `MANE3D_BUILD_SHDC=ON`).
Use `util.compile_shader()` helper - see `examples/breakout.lua`.

Backend detection:
- D3D11 → hlsl5
- Metal → metal_macos
- WGPU → wgsl
- OpenGL → glsl430/glsl300es

## Backends

Auto-selected per platform:
- Windows: D3D11
- macOS: Metal
- Linux: OpenGL
