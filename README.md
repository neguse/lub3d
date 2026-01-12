# Måne3D

A lightweight game framework for Lua 5.5 built on the Sokol ecosystem.

## What Works Now

Thin Lua bindings over Sokol libraries with runtime shader compilation and hot reload.

```lua
local gfx = require("sokol.gfx")
local app = require("sokol.app")

function init()
    shader = util.compile_shader(shader_source, "triangle")
    pipeline = gfx.make_pipeline(gfx.PipelineDesc({ ... }))
end

function frame()
    gfx.begin_pass(...)
    gfx.apply_pipeline(pipeline)
    gfx.draw(0, 3, 1)
    gfx.end_pass()
    gfx.commit()
end
```

### Available Modules

| Module                | Description                                |
| --------------------- | ------------------------------------------ |
| `sokol.gfx`           | Graphics API                               |
| `sokol.app`           | Window/events                              |
| `sokol.gl`            | Immediate mode rendering                   |
| `sokol.debugtext`     | Debug text                                 |
| `sokol.time`          | Timing                                     |
| `sokol.log`           | Logging                                    |
| `sokol.glue`          | gfx/app glue                               |
| `shdc`                | Shader compilation                         |
| `lib.hotreload`       | Hot reload with file watching              |
| `lib.glm`             | GLM-like math (vec2/vec3/vec4/mat4)        |
| `lib.gpu`             | GC-safe GPU resource wrappers              |
| `lib.render_pipeline` | Render pass management with error recovery |

### Supported Backends

- D3D11 (Windows)
- Metal (macOS)
- OpenGL (Linux)
- WebGPU (WASM)

## Build

```bash
# Windows (D3D11)
cmake --preset win-d3d11-debug
cmake --build --preset win-d3d11-debug

# macOS (Metal)
cmake --preset macos-metal-release
cmake --build --preset macos-metal-release

# Linux (OpenGL)
cmake --preset linux-gl-debug
cmake --build --preset linux-gl-debug
```

Run the example:

```bash
./build/win-d3d11-debug/example.exe examples/main.lua
```

See [docs/building.md](docs/building.md) for more options.

## Ideas

Not yet implemented.

### Retained Mode + Auto GC

Pass all resources every frame. Same handle = reuse. Unused handles get garbage collected.

```lua
function frame()
    draw_mesh({
        shader = my_shader_handle,
        mesh = my_mesh_handle,
        transform = transform,
    })
end
```

### Blender as Editor

- Object name = script name (`elevator_01` → `elevator_01.lua`)
- Custom properties for parameters
- glTF export

### Other Ideas

- Fennel + sequence macros

## Design Principles

- **À la carte** - No monolithic framework. Compose from standalone modules.
- **Lua for gameplay, C for performance** - Write game logic fast, optimize hot paths in C.
- **Asset freedom** - No proprietary formats. Generate and modify anything from Lua at runtime.
- **As fast as you type** - Hot reload code, shaders, assets. The tools never slow you down.

## License

MIT
