# CLAUDE.md

## Project Overview

Lübertà3d is a lightweight game framework for Lua 5.5 built on Sokol. Auto-generated C/C++ bindings expose Sokol, Dear ImGui, and Miniaudio to Lua with LuaCATS type annotations.

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
| `LUB3D_BUILD_EXAMPLE` | ON | Example executable |
| `LUB3D_BUILD_SHDC` | ON | sokol-shdc runtime shader compiler |
| `LUB3D_BUILD_IMGUI` | ON | Dear ImGui integration |
| `LUB3D_BUILD_BC7ENC` | ON | BC7 texture encoder |
| `LUB3D_BUILD_TESTS` | OFF | Headless test runner |
| `LUB3D_BUILD_SHARED` | OFF | Shared library (.dll/.so) |
| `LUB3D_BUILD_INTERPRETER` | OFF | Standalone Lua interpreter |
| `LUB3D_USE_SYSTEM_LUA` | OFF | System Lua instead of bundled |
| `LUB3D_BACKEND_*` | auto | `D3D11` / `GL` / `GLES3` / `METAL` / `WGPU` / `DUMMY` |

Backend auto-detection: Windows → D3D11, macOS → Metal, Linux → OpenGL, Emscripten → WGPU.

## Directory Structure

```
lib/                    Lua libraries (require("lib.xxx"))
  glm.lua               vec2/vec3/vec4/mat4 math with LuaCATS annotations
  gpu.lua               GC-safe GPU resource wrappers
  util.lua              Shader compilation, texture loading helpers
  boot.lua              Module bootloader (requires entry script, calls app.Run)
  hotreload.lua         File-watching hot reload via lume.hotswap
  render_pipeline.lua   Render pass management with pcall error recovery
  render_pass.lua       Render pass abstraction
  render_target.lua     Render target utilities
  audio.lua             Shared miniaudio engine creation with VFS (WASM support)
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
  lub3d_lua.c          Module registration entry point
  lub3d_fs.c            File system module (Native fopen/stat, WASM sync XHR)
  lub3d_fs.h            File system module header
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
doc/                    Development documents
  current.md            Current project status
  tasks.md              Pending tasks
  done.md               Completed task log
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
| `lub3d.fs` | — | File system abstraction (Native + WASM) |
| `lub3d.licenses` | — | Third-party license info |

Conditional:

| Module | Flag | Description |
|---|---|---|
| `sokol.imgui` | `LUB3D_BUILD_IMGUI` | ImGui-Sokol integration |
| `imgui` | `LUB3D_BUILD_IMGUI` | Dear ImGui API |
| `shdc` | `LUB3D_BUILD_SHDC` | Runtime shader compiler |
| `bc7enc` | `LUB3D_BUILD_BC7ENC` | BC7 texture encoder |

## Code Generation

**Generator/** — `dotnet run --project Generator -- <output-dir> --deps <deps> --clang <clang>`

Pipeline: Clang AST → TypeRegistry → ModuleSpec → C/C++ bindings + LuaCATS annotations

See [Generator/README.md](Generator/README.md) for design principles.

- Sokol modules: inherit `SokolModule`, override `ModuleName`/`Prefix` + hooks
- Dear ImGui: `IModule` direct, C++ namespace-based, clang++ with `-std=c++17`
- Miniaudio: `IModule` direct, opaque pointer support
- CMake invokes Generator once, outputs all modules to `gen/`

## Running

```bash
build\win-d3d11-debug\examples\lub3d-example.exe examples.hello    # Run specific module
build\win-d3d11-debug\examples\lub3d-example.exe examples.triangle  # Another module
```

The executable takes a Lua module name as argv[1] (default: `examples.hello`). `lib/boot.lua` loads the module via `require()`, extracts `app.Desc` fields from the module table, and calls `app.Run()`.

## Workflow

1. Check `doc/current.md` for the current project status
2. Pick a task from `doc/tasks.md`
3. Design the approach (architecture, scope of impact)
4. Implement and pass tests
5. Record in `doc/done.md`, update `doc/current.md`
6. Create a PR — merge only after Windows build and runtime verification

## Task Format (tasks.md)

```
### Task name
- Background: why this task exists (the problem, motivation)
- Requirements: what "done" looks like (acceptance criteria)
- Approach: chosen design, affected components, key trade-offs
- Alternatives rejected: other options considered and why they were dropped
```

Keep it lightweight — a few bullet points per section is enough. Not every task needs all sections; small bug fixes can skip Approach/Alternatives.

## Completed Task Format (done.md)

```
### Task name ✓ (YYYY-MM-DD)
- What was done (bullet points)
- Files / components changed
- What went well: approaches worth reusing
- Decisions: trade-offs considered, alternatives rejected and why
- Remaining: leftover work (if any)
```

## Development Principles

**Sustainability over speed.** Prioritize code that is readable, fixable, and extensible over shipping fast.
- Reproduce bugs with real data before designing a fix. Investigate the root cause, not just the symptoms.
- A task is not done until tests pass, design decisions are recorded, and docs are updated.
- Finalize task names after investigation. Use a tentative title during the hypothesis phase; update tasks.md once the root cause is identified.
- **PRs required**: Direct pushes to master are not allowed. Always branch and go through a PR, since Windows compilation and runtime verification are necessary.

## Conventions

- **Require paths**: root-relative (`require("lib.util")`, `require("examples.deferred.camera")`). Do NOT manipulate `package.path`.
- **Module return pattern**: Lua scripts return a module table `M` with desc fields (`width`, `height`, `window_title`, etc.) and callback methods (`M:init()`, `M:frame()`, `M:event(ev)`, `M:cleanup()`). `lib/boot.lua` handles `app.Run()`.
- **Shader compilation**: `util.compile_shader()` with auto backend detection (D3D11→hlsl5, Metal→metal_macos, WGPU→wgsl, GL→glsl430/glsl300es). Requires `LUB3D_BUILD_SHDC=ON`.

## Asset Pipeline

```bash
uv venv .venv && uv pip install panda3d
.venv/Scripts/python scripts/bam2egg.py
.venv/Scripts/python scripts/egg2lua.py <input.egg> <output.lua>
```

Assets load textures relative to scene: `assets/<scene>/tex/<texture>.png`. Shared images in `assets/images/`.
