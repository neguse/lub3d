# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Måne3D is a lightweight game framework for Lua 5.5 + Fennel built on top of the Sokol graphics ecosystem. Core philosophy:

- C API as the stable foundation
- Declarative resource management with React-like caching and diffing
- Blender as the primary editor (no custom editor)
- Thin wrappers over Sokol libraries

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
./check.sh    # Linux/macOS (requires lua-language-server)
check.bat     # Windows
```

### CMake Options

- `MANE3D_BUILD_SHARED` - Build as shared library (default: OFF)
- `MANE3D_BUILD_EXAMPLE` - Build example executable (default: OFF)
- `MANE3D_USE_SYSTEM_LUA` - Use system Lua instead of bundled (default: OFF)

## Architecture

### Code Generation Pipeline

`gen_lua.py` automatically generates Lua bindings from Sokol headers:

- Parses Sokol headers using sokol/bindgen tools
- Generates C modules in `gen/bindings/sokol_*.c`
- Generates Lua type stubs in `gen/types/sokol/*.lua` for IDE support

### Directory Structure

- `gen/` - Generated files (gitignored)
  - `bindings/` - Lua binding C implementations
  - `types/` - Lua type definitions for IDE autocomplete
  - `stubs/` - Temporary files for code generation
- `src/` - Manual source files (sokol_impl.c)
- `examples/` - Sample applications and shaders
- `deps/` - Git submodules (lua, sokol)

### Sokol Modules

The framework exposes these Sokol modules to Lua:

- `sokol.gfx` - Graphics/rendering
- `sokol.app` - Window and event handling
- `sokol.gl` - Immediate-mode graphics
- `sokol.audio` - Audio playback
- `sokol.time` - Timing utilities
- `sokol.debugtext` - Debug text rendering
- `sokol.log` - Logging

### Event Loop Model

Lua scripts implement four callbacks:

- `init()` - One-time initialization
- `frame()` - Per-frame rendering
- `event(ev)` - Input/window events
- `cleanup()` - Shutdown

### Shader Compilation

Runtime shader compilation via sokol-shdc. Backend detection in `examples/util.lua`:

- D3D11 → hlsl5
- Metal → metal_macos
- WGPU → wgsl
- OpenGL → glsl430/glsl300es

## Dependencies

Git submodules in `deps/`:

- `lua/` - Lua 5.5 source
- `sokol/` - Sokol headers and tools

Backends are auto-selected per platform (D3D11 on Windows, Metal on macOS, OpenGL on Linux).
