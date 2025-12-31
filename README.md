# Måne

A lightweight game framework for Lua 5.5 + Fennel.

## Philosophy

- **C API is everything** - Stable C layer, anything can sit on top
- **Declarative resource management** - Declare what you use each frame, caching and diffing handled internally
- **Blender as editor** - No custom editor, integrate with Blender
- **Thin wrappers** - Don't over-abstract, drop down to low-level APIs when needed

## Stack

| Area         | Library                   |
| ------------ | ------------------------- |
| Graphics     | sokol_gfx, sokol_app      |
| Physics (3D) | Jolt Physics (C wrapper)  |
| Physics (2D) | Box2D                     |
| Animation    | ozz-animation (C wrapper) |
| Audio        | miniaudio                 |
| Font         | fontstash + stb_truetype  |
| Shaders      | sokol-shdc (precompiled)  |

All C header-based. Unified bindgen pipeline generates Lua bindings.

## Backends

- Metal (macOS/iOS)
- D3D11 (Windows)
- Vulkan (Linux/Windows)
- WebGPU (Browser)

No WebGL2. We want compute shaders.

## Scripting

Lua 5.5 or Fennel.

Fennel macros for sequences:

```fennel
(seq
  (flash-lines)
  (wait 0.3)
  (clear-lines))
```

Compiles to data. State survives hot reload.

## Resource Management

React-like.

```lua
function draw()
  local mesh = use_mesh("player.glb")
  local shader = use_shader("skin.glsl")
  draw_mesh(mesh, shader, transform)
end
```

- Same ID = reuse existing resource
- Change ID = recreate
- Unreferenced = garbage collected on scene change

## Blender Integration

- **Naming convention** - Object name = script name (`elevator_01` → `elevator_01.lua`)
- **Custom properties** - Edit parameters in Blender
- **Live link** - Changes reflect immediately
- **glTF export** - Standard format, lightweight

```
Double-click in Blender → Opens script in VSCode
```

## Shaders

sokol-shdc for precompilation. GLSL → Metal/HLSL/SPIR-V/WGSL.

Compute shader support. SSAO and other post-processing.

## Build

```
make          # Native
make web      # WASM + WebGPU
```

Same codebase outputs to web via Emscripten.

## Status

Initial target: D3D11 (Windows) + WebGPU only.

| Feature                         | Status      |
| ------------------------------- | ----------- |
| sokol bindings                  | Done        |
| Runtime shader compilation      | Done        |
| WebGPU backend                  | Not started |
| glTF loader                     | Not started |
| Declarative resources (`use_*`) | Not started |
| Fennel support                  | Not started |
| Hot reload                      | Not started |
| miniaudio                       | Not started |
| fontstash                       | Not started |
| Box2D                           | Not started |
| Jolt Physics                    | Not started |
| ozz-animation                   | Not started |
| Blender integration             | Not started |

## Non-Goals

- Scene graphs
- Visual scripting
- Custom editor
- USD support

## License

MIT
