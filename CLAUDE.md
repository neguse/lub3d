# CLAUDE.md

## Project Overview

Måne3D is a lightweight game framework for Lua 5.5 built on Sokol. Auto-generated C/C++ bindings expose Sokol, Dear ImGui, and Miniaudio to Lua with LuaCATS type annotations.

## Build

```bash
scripts\build.bat                    # Windows default (win-d3d11-debug)
scripts\build.bat win-d3d11-release  # Specify preset
dotnet test Generator.Tests          # Generator unit tests (338 tests)
scripts\run_tests.bat                # Headless example tests (13 tests)
python scripts/check.py              # Lua type-check (lua-language-server)
python scripts/check.py --doc        # Lua type-check + doc.json generation
```

Presets: `win-d3d11-{debug,release}`, `win-gl-debug`, `win-dummy-{debug,release}`, `macos-metal-release`, `linux-gl-debug`, `linux-dummy-{debug,release}`, `wasm-{debug,release}`

### CMake Options

| Option | Default | Description |
|---|---|---|
| `MANE3D_BUILD_EXAMPLE` | ON | Example executable |
| `MANE3D_BUILD_SHDC` | ON | sokol-shdc runtime shader compiler |
| `MANE3D_BUILD_IMGUI` | ON | Dear ImGui integration |
| `MANE3D_BUILD_BC7ENC` | ON | BC7 texture encoder |
| `MANE3D_BUILD_TESTS` | OFF | Headless test runner |
| `MANE3D_BUILD_SHARED` | OFF | Shared library (.dll/.so) |
| `MANE3D_BUILD_INTERPRETER` | OFF | Standalone Lua interpreter |
| `MANE3D_USE_SYSTEM_LUA` | OFF | System Lua instead of bundled |
| `MANE3D_BACKEND_*` | auto | `D3D11` / `GL` / `GLES3` / `METAL` / `WGPU` / `DUMMY` |

Backend auto-detection: Windows → D3D11, macOS → Metal, Linux → OpenGL, Emscripten → WGPU.

## Directory Structure

```
lib/                    Lua libraries (require("lib.xxx"))
  glm.lua               vec2/vec3/vec4/mat4 math with LuaCATS annotations
  gpu.lua               GC-safe GPU resource wrappers
  util.lua              Shader compilation, texture loading helpers
  hotreload.lua         File-watching hot reload via lume.hotswap
  render_pipeline.lua   Render pass management with pcall error recovery
  render_pass.lua       Render pass abstraction
  render_target.lua     Render target utilities
  shader.lua            Shader utilities
  texture.lua           Texture utilities
  headless_app.lua      Headless mode app stub
  notify.lua            Notification utilities
  log.lua               Logging utilities
gen/                    Generated files (gitignored, output of C# Generator)
  sokol_*.c / .lua      Sokol binding C code + LuaCATS annotations
  imgui_gen.cpp / imgui.lua   Dear ImGui bindings
  miniaudio.c / .lua    Miniaudio bindings
  licenses.c            Third-party license data (gen_licenses.py)
src/                    Manual C/C++ source
  sokol_impl.c          Sokol implementation defines
  miniaudio_impl.c      Miniaudio implementation
  mane3d_lua.c          Module registration entry point
  stb_image_lua.c       stb_image Lua bindings
  imgui_impl.cpp        Dear ImGui core implementation
  imgui_sokol.cpp       ImGui-Sokol integration
  bc7enc_lua.cpp        BC7 encoder Lua bindings
  shdc_wrapper.cc       sokol-shdc C++ wrapper
  shdc_lua.c            Shader compiler Lua bindings
Generator/              C# (.NET 10) binding generator
  ClangAst/             Clang AST parsing → TypeRegistry
  CBinding/             C/C++ code generation
  LuaCats/              LuaCATS type annotation generation
  Modules/Sokol/        10 Sokol modules (SokolModule base class)
  Modules/Imgui/        Dear ImGui module (IModule direct, clang++)
  Modules/Miniaudio/    Miniaudio module
  Program.cs            CLI entry point
Generator.Tests/        xUnit tests (Assert.Contains-based)
scripts/
  build.bat             Windows build (auto-detects VS, clang)
  run_tests.bat/.sh     Headless example test runner
  gen_licenses.py       License data generator
  bam2egg.py            .bam → .egg asset converter
  egg2lua.py            .egg → Lua model data
deps/                   Git submodules
  lua/                  Lua 5.5
  sokol/                Sokol headers
  sokol-tools/          sokol-shdc source
  imgui/                Dear ImGui
  miniaudio/            Miniaudio
  stb/                  stb_image
  bc7enc_rdo/           BC7 encoder
  3d-game-shaders-for-beginners/  Reference shaders/assets
examples/               Sample Lua applications
```

## Lua Modules

Always available:

| Module | Prefix | Description |
|---|---|---|
| `sokol.gfx` | `sg_` | Graphics/rendering |
| `sokol.app` | `sapp_` | Window and events |
| `sokol.glue` | `sglue_` | App↔Gfx glue |
| `sokol.log` | `slog_` | Logging |
| `sokol.time` | `stm_` | Timing |
| `sokol.gl` | `sgl_` | Immediate-mode graphics |
| `sokol.debugtext` | `sdtx_` | Debug text |
| `sokol.audio` | `saudio_` | Audio playback |
| `sokol.shape` | `sshape_` | Shape generation |
| `miniaudio` | — | Audio engine |
| `stb.image` | — | Image loading |
| `mane3d.licenses` | — | Third-party license info |

Conditional:

| Module | Flag | Description |
|---|---|---|
| `sokol.imgui` | `MANE3D_BUILD_IMGUI` | ImGui-Sokol integration |
| `imgui` | `MANE3D_BUILD_IMGUI` | Dear ImGui API |
| `shdc` | `MANE3D_BUILD_SHDC` | Runtime shader compiler |
| `bc7enc` | `MANE3D_BUILD_BC7ENC` | BC7 texture encoder |

## Code Generation

**Generator/** — `dotnet run --project Generator -- <output-dir> --deps <deps> --clang <clang>`

Pipeline: Clang AST → TypeRegistry → ModuleSpec → C/C++ bindings + LuaCATS annotations

- Sokol modules: inherit `SokolModule`, override `ModuleName`/`Prefix` + hooks
- Dear ImGui: `IModule` direct, C++ namespace-based, clang++ with `-std=c++17`
- Miniaudio: `IModule` direct, opaque pointer support
- CMake invokes Generator once, outputs all modules to `gen/`

## Conventions

- **Require paths**: root-relative (`require("lib.util")`, `require("examples.deferred.camera")`). Do NOT manipulate `package.path`.
- **Event loop**: Lua scripts implement `init()`, `frame()`, `event(ev)`, `cleanup()` callbacks.
- **Shader compilation**: `util.compile_shader()` with auto backend detection (D3D11→hlsl5, Metal→metal_macos, WGPU→wgsl, GL→glsl430/glsl300es). Requires `MANE3D_BUILD_SHDC=ON`.

## Asset Pipeline

```bash
uv venv .venv && uv pip install panda3d
.venv/Scripts/python scripts/bam2egg.py
.venv/Scripts/python scripts/egg2lua.py <input.egg> <output.lua>
```

Assets load textures relative to scene: `assets/<scene>/tex/<texture>.png`. Shared images in `assets/images/`.
